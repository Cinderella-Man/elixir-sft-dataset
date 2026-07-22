# Write the missing @spec

Below is a complete, working module — except that the `@spec` for
`execute/3` has been removed; its place is marked `# TODO: @spec`.
Write exactly that typespec: one `@spec` attribute for `execute/3`,
consistent with the function's arguments, guards, and every return shape
the implementation can produce. Change nothing else.

## The module with the `@spec` for `execute/3` missing

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
  # TODO: @spec
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
    timeout = Keyword.get(opts, :attempt_timeout_ms, 5_000)

    # The timeout runs INSIDE the wrapper task, which owns the inner task
    # and may therefore yield to and shut it down; the server never blocks.
    # A crash in `func` kills the linked wrapper with the same reason, so
    # it surfaces at the server as this task's :DOWN — the
    # `{:task_crashed, reason}` path.
    task =
      Task.Supervisor.async_nolink(state.supervisor, fn ->
        inner = Task.async(fn -> func.() end)

        case Task.yield(inner, timeout) do
          {:ok, result} ->
            result

          nil ->
            _ = Task.shutdown(inner, :brutal_kill)
            {:error, :timeout}
        end
      end)

    record = %{from: from, func: func, attempt: attempt, opts: opts}
    %{state | tasks: Map.put(state.tasks, task.ref, record)}
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

Give me only the `@spec` attribute — the attribute alone (however many
lines it spans), not the whole module.
