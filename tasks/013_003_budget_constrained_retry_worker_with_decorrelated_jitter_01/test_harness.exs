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
    func = fail_then_succeed(5, :nope)

    assert {:error, :budget_exhausted, :boom, 1} =
             BudgetRetryWorker.execute(rw, func,
               budget_ms: 0,
               base_delay_ms: 100
             )
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
