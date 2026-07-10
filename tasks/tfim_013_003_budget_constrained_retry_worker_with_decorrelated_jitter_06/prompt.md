# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule BudgetRetryWorker do
  @moduledoc """
  A GenServer that executes functions with retries governed by a total time
  budget and decorrelated jitter (AWS-style backoff).
  """

  use GenServer

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Runs `func`, retrying with decorrelated-jitter backoff until it succeeds or the retry
  budget in `opts` is exhausted.
  """
  @spec execute(GenServer.server(), (-> any()), keyword()) ::
          {:ok, any()} | {:error, :budget_exhausted, any(), pos_integer()}
  def execute(server, func, opts \\ []) do
    GenServer.call(server, {:execute, func, opts}, :infinity)
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.monotonic_time(:millisecond) end)

    random =
      Keyword.get(opts, :random, fn min, max ->
        min + :rand.uniform(max - min + 1) - 1
      end)

    {:ok, %{clock: clock, random: random}}
  end

  @impl true
  def handle_call({:execute, func, opts}, from, state) do
    clock_fn = state.clock
    random_fn = state.random

    spawn_link(fn ->
      result = retry_loop(func, opts, clock_fn, random_fn)
      GenServer.reply(from, result)
    end)

    {:noreply, state}
  end

  # --- Private Helpers ---

  defp retry_loop(func, opts, clock_fn, random_fn) do
    started_at = clock_fn.()
    base_delay = Keyword.get(opts, :base_delay_ms, 100)
    budget = Keyword.get(opts, :budget_ms, 30_000)
    max_delay = Keyword.get(opts, :max_delay_ms, 10_000)

    do_attempt(
      func,
      clock_fn,
      random_fn,
      started_at,
      base_delay,
      budget,
      max_delay,
      base_delay,
      0
    )
  end

  defp do_attempt(
         func,
         clock_fn,
         random_fn,
         started_at,
         base_delay,
         budget,
         max_delay,
         prev_delay,
         attempts
       ) do
    attempts = attempts + 1

    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        now = clock_fn.()
        elapsed = now - started_at

        jitter_max = prev_delay * 3
        next_delay = random_fn.(base_delay, jitter_max)
        capped_delay = min(next_delay, max_delay)

        if elapsed + capped_delay > budget do
          {:error, :budget_exhausted, reason, attempts}
        else
          target_time = now + capped_delay
          await_clock(target_time, clock_fn)

          do_attempt(
            func,
            clock_fn,
            random_fn,
            started_at,
            base_delay,
            budget,
            max_delay,
            capped_delay,
            attempts
          )
        end
    end
  end

  defp await_clock(target_time, clock_fn) do
    if clock_fn.() < target_time do
      receive do
      after
        0 -> await_clock(target_time, clock_fn)
      end
    end
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule BudgetRetryWorkerTest do
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

  # --- Deterministic random that always returns the minimum ---

  defmodule MinRandom do
    def rand(min, _max), do: min
  end

  # --- Counter ---

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
      BudgetRetryWorker.start_link(
        clock: &Clock.now/0,
        random: &MinRandom.rand/2
      )

    %{rw: pid}
  end

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
             BudgetRetryWorker.execute(rw, func,
               budget_ms: 10_000,
               base_delay_ms: 100
             )
  end

  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             BudgetRetryWorker.execute(rw, func,
               budget_ms: 10_000,
               base_delay_ms: 100
             )

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Retries then succeeds within budget
  # -------------------------------------------------------

  test "retries and succeeds within the time budget", %{rw: rw} do
    func = fail_then_succeed(2, :recovered)

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 10_000,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # With MinRandom, decorrelated jitter returns base_delay each time
    # retry 1: delay = min(100, 10000) = 100
    Process.sleep(20)
    Clock.advance(100)
    # retry 2: prev_delay=100, delay = min(100, 10000) = 100
    Process.sleep(20)
    Clock.advance(100)

    assert {:ok, :recovered} = Task.await(task, 5_000)
    assert Counter.get() == 3
  end

  # -------------------------------------------------------
  # Budget exhausted
  # -------------------------------------------------------

  test "returns budget_exhausted when time runs out", %{rw: rw} do
    func = fail_then_succeed(100, :never)

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 250,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # Initial attempt fails at t=0. Next delay = 100.
    # elapsed(0) + 100 <= 250 → schedule retry
    Process.sleep(20)
    Clock.advance(100)

    # Attempt 2 at t=100 fails. Next delay = 100.
    # elapsed(100) + 100 = 200 <= 250 → schedule retry
    Process.sleep(20)
    Clock.advance(100)

    # Attempt 3 at t=200 fails. Next delay = 100.
    # elapsed(200) + 100 = 300 > 250 → budget exhausted
    Process.sleep(20)

    assert {:error, :budget_exhausted, :boom, attempts} = Task.await(task, 5_000)
    assert attempts == 3
  end

  test "zero budget means only one attempt", %{rw: rw} do
    # TODO
  end

  # -------------------------------------------------------
  # Delay capping with max_delay_ms
  # -------------------------------------------------------

  test "max_delay_ms caps the computed delay", %{rw: _rw} do
    start_supervised!({Counter, 0})
    test_pid = self()

    # Use a random that always returns the max (prev_delay * 3)
    # to exercise the cap
    max_random = fn _min, max -> max end

    {:ok, rw2} =
      BudgetRetryWorker.start_link(
        clock: &Clock.now/0,
        random: max_random
      )

    func = fn ->
      attempt = Counter.increment_and_get()
      send(test_pid, {:attempt, attempt, Clock.now()})

      if attempt <= 3, do: {:error, :fail}, else: {:ok, :done}
    end

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw2, func,
          budget_ms: 100_000,
          base_delay_ms: 100,
          max_delay_ms: 500
        )
      end)

    # Attempt 1 at t=0. prev=100, next=random(100,300)=300, capped=min(300,500)=300
    assert_receive {:attempt, 1, _}
    Clock.advance(300)

    # Attempt 2 at t=300. prev=300, next=random(100,900)=900, capped=min(900,500)=500
    assert_receive {:attempt, 2, _}
    Clock.advance(500)

    # Attempt 3 at t=800. prev=500, next=random(100,1500)=1500, capped=min(1500,500)=500
    assert_receive {:attempt, 3, _}
    Clock.advance(500)

    assert_receive {:attempt, 4, _}

    assert {:ok, :done} = Task.await(task, 5_000)
  end

  # -------------------------------------------------------
  # Concurrent executions are independent
  # -------------------------------------------------------

  test "multiple concurrent executions don't block each other", %{rw: rw} do
    func1 = fn -> {:ok, :fast} end

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n <= 1, do: {:error, :not_yet}, else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func1,
          budget_ms: 10_000,
          base_delay_ms: 100
        )
      end)

    task2 =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func2,
          budget_ms: 10_000,
          base_delay_ms: 100
        )
      end)

    assert {:ok, :fast} = Task.await(task1, 2_000)

    # Advance clock for func2's retry
    Process.sleep(50)
    Clock.advance(200)

    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Attempt count is accurate
  # -------------------------------------------------------

  test "attempt count reflects all tries made", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 350,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # With MinRandom: delay is always base_delay=100
    # t=0: attempt 1 fails, schedule at +100
    Process.sleep(20)
    Clock.advance(100)
    # t=100: attempt 2 fails, elapsed(100)+100=200 <= 350, schedule
    Process.sleep(20)
    Clock.advance(100)
    # t=200: attempt 3 fails, elapsed(200)+100=300 <= 350, schedule
    Process.sleep(20)
    Clock.advance(100)
    # t=300: attempt 4 fails, elapsed(300)+100=400 > 350, exhausted
    Process.sleep(20)

    assert {:error, :budget_exhausted, _reason, 4} = Task.await(task, 5_000)

    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = BudgetRetryWorker.execute(rw, func, [])
  end
end
```
