Implement the private `handle_task_result_sync/6` function. It takes `(result, func, attempt, opts, from, state)` and decides what to do with the outcome of a single attempt, replying to the caller and/or scheduling a retry.

It should read the `:max_retries` option from `opts` (default 3). Then branch on `result`:

- If `result` is `{:ok, value}`, the execution succeeded: reply to the caller with `GenServer.reply(from, {:ok, value})` and return `{:ok, state}`.
- If `result` is `{:error, reason}`, the attempt failed. Compare the current `attempt` (0-indexed) against `max_retries`:
  - If `attempt >= max_retries`, retries are exhausted: reply with `GenServer.reply(from, {:error, :max_retries_exceeded, reason})` and return `{:exhausted, state}`.
  - Otherwise, schedule the next attempt via `schedule_retry(func, attempt + 1, opts, from, state)` and return `{:retrying, state}`.

The returned tuple's first element (`:ok` / `:exhausted` / `:retrying`) is a status tag used by callers; the second element is the (unchanged) state. This helper both handles the synchronous path from `launch_attempt/5` and is reused by `handle_task_result/6` for the asynchronous path.

```elixir
defmodule TimeoutRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff, jitter,
  and per-attempt timeouts enforced via Task.yield/Task.shutdown.

  Each attempt runs inside a supervised, unlinked Task so that an abnormal
  exit in the user function cannot bring down the worker; such an exit is
  surfaced as a retryable `{:task_crashed, reason}` failure.
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
    state = launch_attempt(func, 0, opts, from, state)
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

    task = Task.Supervisor.async_nolink(state.supervisor, fn -> func.() end)

    outcome =
      case Task.yield(task, timeout) do
        {:ok, result} ->
          result

        {:exit, reason} ->
          {:error, {:task_crashed, reason}}

        nil ->
          _ = Task.shutdown(task, :brutal_kill)
          {:error, :timeout}
      end

    {_, state} = handle_task_result_sync(outcome, func, attempt, opts, from, state)
    state
  end

  defp handle_task_result_sync(result, func, attempt, opts, from, state) do
    # TODO
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