# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule TimeoutRetryWorkerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  # --- Fake random that always returns 0 (no jitter) ---

  defmodule ZeroRandom do
    def rand(_max), do: 0
  end

  # --- Counter to build "fail N times then succeed" functions ---

  defmodule Counter do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def increment_and_get do
      Agent.get_and_update(__MODULE__, fn n -> {n + 1, n + 1} end)
    end

    def get, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      TimeoutRetryWorker.start_link(
        clock: &Clock.now/0,
        random: &ZeroRandom.rand/1
      )

    %{rw: pid}
  end

  # Helper: build a function that fails `n` times then succeeds with `value`
  defp fail_then_succeed(n, value) do
    start_supervised!({Counter, 0})

    fn ->
      attempt = Counter.increment_and_get()

      if attempt <= n do
        {:error, :boom}
      else
        {:ok, value}
      end
    end
  end

  # -------------------------------------------------------
  # Immediate success
  # -------------------------------------------------------

  test "returns immediately when function succeeds on first try", %{rw: rw} do
    func = fn -> {:ok, 42} end

    assert {:ok, 42} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )
  end

  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Retries then succeeds
  # -------------------------------------------------------

  test "retries and succeeds on the Nth attempt", %{rw: rw} do
    func = fail_then_succeed(3, :recovered)

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    # 3 failures + 1 success = 4 total calls
    assert Counter.get() == 4
  end

  test "succeeds on the very last retry", %{rw: rw} do
    func = fail_then_succeed(3, :last_chance)

    assert {:ok, :last_chance} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 4
  end

  # -------------------------------------------------------
  # Max retries exhausted
  # -------------------------------------------------------

  test "returns error when all retries are exhausted", %{rw: rw} do
    func = fail_then_succeed(10, :never)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 4
  end

  test "max_retries of 0 means no retries at all", %{rw: rw} do
    func = fail_then_succeed(5, :nope)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 0,
               base_delay_ms: 100,
               attempt_timeout_ms: 5_000
             )

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Per-attempt timeout enforcement
  # -------------------------------------------------------

  test "times out a slow function and retries", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 1 do
        # Simulate a hang — sleep longer than the timeout
        Process.sleep(500)
        {:ok, :should_not_reach}
      else
        {:ok, :recovered_after_timeout}
      end
    end

    assert {:ok, :recovered_after_timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 2
  end

  test "returns timeout as last reason when all attempts time out", %{rw: rw} do
    func = fn ->
      Process.sleep(500)
      {:ok, :never_reaches}
    end

    assert {:error, :max_retries_exceeded, :timeout} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 50
             )
  end

  # -------------------------------------------------------
  # Concurrent executions are independent
  # -------------------------------------------------------

  test "multiple concurrent executions don't block each other", %{rw: rw} do
    # func1 succeeds immediately
    func1 = fn -> {:ok, :fast} end

    # func2 fails once then succeeds
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n <= 1, do: {:error, :not_yet}, else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func1,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    task2 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func2,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    # func1 should return immediately
    assert {:ok, :fast} = Task.await(task1, 2_000)

    # func2 retries and eventually succeeds
    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Propagates the last error reason
  # -------------------------------------------------------

  test "returns the last error reason on exhaustion", %{rw: rw} do
    # TODO
  end

  # -------------------------------------------------------
  # Timeout mixed with normal errors
  # -------------------------------------------------------

  test "timeout on first attempt then error then success", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      case attempt do
        1 ->
          Process.sleep(500)
          {:ok, :too_slow}

        2 ->
          {:error, :transient_failure}

        _ ->
          {:ok, :finally}
      end
    end

    assert {:ok, :finally} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 50,
               attempt_timeout_ms: 100
             )

    assert Counter.get() == 3
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = TimeoutRetryWorker.execute(rw, func, [])
  end
end
```
