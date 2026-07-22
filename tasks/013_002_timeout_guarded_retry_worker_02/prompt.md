Implement the private `launch_attempt/5` function. It runs a single attempt of the
provided zero-arity `func` inside a spawned `Task`, enforcing a per-attempt timeout.

It receives `(func, attempt, opts, from, state)`. Read the timeout from `opts` using
the `:attempt_timeout_ms` key (default `5_000`). Start the attempt with `Task.async/1`
running `func.()`, then wait for it with `Task.yield/2` using that timeout.

- If the task completes in time, `Task.yield/2` returns `{:ok, result}`. Demonitor the
  task's reference with `Process.demonitor(task.ref, [:flush])` (to drop any pending
  `:DOWN` message), then hand `result` off to `handle_task_result_sync/6` with the same
  `func`, `attempt`, `opts`, `from`, and `state`.
- If the task does not complete in time, `Task.yield/2` returns `nil`. Shut the task down
  with `Task.shutdown(task, :brutal_kill)` and treat it as an `{:error, :timeout}` failure
  by passing that to `handle_task_result_sync/6`.

`handle_task_result_sync/6` returns a `{status, state}` tuple; in both branches discard the
status and return the (possibly updated) `state`, since `launch_attempt/5` is expected to
return the new state.

```elixir
defmodule TimeoutRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff, jitter,
  and per-attempt timeouts enforced via Task.yield/Task.shutdown.

  Each attempt runs inside a supervised, unlinked Task so that an abnormal
  exit in the user function cannot bring down the worker; such an exit is
  surfaced as a retryable `{:task_crashed, reason}` failure.

  The per-attempt timeout is enforced INSIDE the attempt task by a nested
  `Task.yield/2` + `Task.shutdown/2` pair, and outcomes come back as plain
  task messages routed through per-execution records keyed by task ref —
  the server itself never blocks, so no caller's slow attempt or backoff
  wait delays another caller's reply.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @doc "Starts the worker. Accepts `:name`, `:clock`, and `:random` options."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc "Runs `func`, retrying on failure until the timeout in `opts`. Returns the result."
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, any()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)
    random = Keyword.get(opts, :random, fn max -> :rand.uniform(max) - 1 end)
    {:ok, supervisor} = Task.Supervisor.start_link()
    {:ok, %{clock: clock, random: random, supervisor: supervisor, tasks: %{}}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    # Attempt 0 launches from handle_info exactly like every retry — the
    # contract pins "spawned from within the GenServer's handle_info".
    send(self(), {:retry, func, 0, opts, from})
    {:noreply, state}
  end

  @impl true
  def handle_info({:retry, func, attempt, opts, from}, state) do
    state = launch_attempt(func, attempt, opts, from, state)
    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    # Defensive: a stray result for an execution we no longer track is ignored.
    Process.demonitor(ref, [:flush])

    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result(result, func, attempt, opts, from, state)
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case Map.pop(state.tasks, ref) do
      {nil, _} ->
        {:noreply, state}

      {%{from: from, func: func, attempt: attempt, opts: opts}, new_tasks} ->
        state = %{state | tasks: new_tasks}
        handle_task_result({:error, {:task_crashed, reason}}, func, attempt, opts, from, state)
    end
  end

  # --- Private Helpers ---

  defp launch_attempt(func, attempt, opts, from, state) do
    # TODO
  end

  defp handle_task_result_sync(result, func, attempt, opts, from, state) do
    max_retries = Keyword.get(opts, :max_retries, 3)

    case result do
      {:ok, value} ->
        GenServer.reply(from, {:ok, value})
        {:ok, state}

      {:error, reason} ->
        if attempt >= max_retries do
          GenServer.reply(from, {:error, :max_retries_exceeded, reason})
          {:exhausted, state}
        else
          schedule_retry(func, attempt + 1, opts, from, state)
          {:retrying, state}
        end
    end
  end

  defp handle_task_result(result, func, attempt, opts, from, state) do
    {_, new_state} = handle_task_result_sync(result, func, attempt, opts, from, state)
    {:noreply, new_state}
  end

  defp schedule_retry(func, next_attempt, opts, from, state) do
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    n = next_attempt - 1
    shift = min(n, 50)
    delay = min(base_delay <<< shift, max_delay)

    jitter = if delay > 0, do: state.random.(delay), else: 0
    total_wait = delay + jitter

    Process.send_after(self(), {:retry, func, next_attempt, opts, from}, total_wait)
  end
end
```