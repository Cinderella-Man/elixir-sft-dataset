Implement the private `schedule_retry/5` function. It receives the zero-arity `func`,
the `next_attempt` number (1-indexed for retries), the `opts` keyword list, the caller's
`from` reference, and the GenServer `state`. It must compute the exponential backoff delay
and schedule a `{:retry, func, next_attempt, opts, from}` message to be delivered to the
current process after that delay, so the GenServer stays free to serve other callers while
waiting.

Read `:base_delay_ms` (default `100`) and `:max_delay_ms` (default `10_000`) from `opts`.
The backoff for a retry is based on the 0-indexed attempt exponent `n = next_attempt - 1`.
Compute `delay = min(base_delay_ms * 2^n, max_delay_ms)` — use a left bit-shift for the
power of two, clamping the shift amount to at most `50` to avoid pathological shifts. Then
add random jitter: when `delay > 0`, obtain the jitter by calling the injected random
function `state.random` with `delay` as its argument (yielding a value in `0..delay-1`),
otherwise use `0`. The total wait is `delay + jitter`.

Finally, use `Process.send_after/3` targeting `self()` to deliver the retry message after
`total_wait` milliseconds, and return whatever it returns.

```elixir
defmodule TimeoutRetryWorker do
  @moduledoc """
  A GenServer that executes functions with exponential backoff, jitter,
  and per-attempt timeouts enforced via Task.yield/Task.shutdown.
  """

  use GenServer
  import Bitwise

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

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
    {:ok, %{clock: clock, random: random, tasks: %{}}}
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
    # Task completed normally — flush the :DOWN message
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

    task = Task.async(fn -> func.() end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        # Completed within timeout — handle synchronously
        Process.demonitor(task.ref, [:flush])
        {_, state} = handle_task_result_sync(result, func, attempt, opts, from, state)
        state

      nil ->
        # Timed out — shut it down
        Task.shutdown(task, :brutal_kill)
        {_, state} = handle_task_result_sync({:error, :timeout}, func, attempt, opts, from, state)
        state
    end
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
    # TODO
  end
end
```