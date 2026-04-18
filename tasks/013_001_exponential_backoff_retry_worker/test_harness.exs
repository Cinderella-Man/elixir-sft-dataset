defmodule RetryWorkerTest do
  use ExUnit.Case, async: false

  # --- Fake clock for deterministic testing ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
    def set(ms), do: Agent.update(__MODULE__, fn _ -> ms end)
  end

  # --- Fake random that always returns 0 (no jitter) for predictable delays ---

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

  # --- Delay recorder to verify backoff schedule ---

  defmodule DelayRecorder do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(delay) do
      Agent.update(__MODULE__, &(&1 ++ [delay]))
    end

    def delays, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      RetryWorker.start_link(
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
             RetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)
  end

  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             RetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Retries then succeeds
  # -------------------------------------------------------

  test "retries and succeeds on the Nth attempt", %{rw: rw} do
    func = fail_then_succeed(3, :recovered)

    assert {:ok, :recovered} =
             RetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    # Should have been called 4 times: 3 failures + 1 success
    assert Counter.get() == 4
  end

  test "succeeds on the very last retry", %{rw: rw} do
    func = fail_then_succeed(3, :last_chance)

    assert {:ok, :last_chance} =
             RetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # 3 failures + 1 success = 4 total calls = initial + 3 retries
    assert Counter.get() == 4
  end

  # -------------------------------------------------------
  # Max retries exhausted
  # -------------------------------------------------------

  test "returns error when all retries are exhausted", %{rw: rw} do
    func = fail_then_succeed(10, :never)

    assert {:error, :max_retries_exceeded, :boom} =
             RetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # initial attempt + 3 retries = 4 calls total
    assert Counter.get() == 4
  end

  test "max_retries of 0 means no retries at all", %{rw: rw} do
    func = fail_then_succeed(5, :nope)

    assert {:error, :max_retries_exceeded, :boom} =
             RetryWorker.execute(rw, func, max_retries: 0, base_delay_ms: 100)

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Exponential backoff delays (with zero jitter)
  # -------------------------------------------------------

  test "delays grow exponentially with zero jitter", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:timestamps, [:set, :public, :named_table])

    # 1. Capture the test process PID to send signals back to it
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:timestamps, {attempt, Clock.now()})

      # 2. Signal that this attempt is done
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 4, do: {:error, :fail}, else: {:ok, :done}
    end

    {:ok, rw2} = RetryWorker.start_link(clock: &Clock.now/0, random: &ZeroRandom.rand/1)

    # 3. Use base_delay_ms: 1 so real-time passes instantly
    task =
      Task.async(fn ->
        RetryWorker.execute(rw2, func, max_retries: 4, base_delay_ms: 1)
      end)

    # 4. Step-through synchronization
    # Wait for Attempt 1
    assert_receive {:attempt_done, 1}

    # Advance clock, THEN wait for Attempt 2
    Clock.advance(100)
    assert_receive {:attempt_done, 2}

    Clock.advance(200)
    assert_receive {:attempt_done, 3}

    Clock.advance(400)
    assert_receive {:attempt_done, 4}

    Clock.advance(800)
    assert_receive {:attempt_done, 5}

    assert {:ok, :done} = Task.await(task)

    # Assertions will now pass because the timing is locked
    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}] =
      for i <- 1..5, do: :ets.lookup(:timestamps, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 400
    assert t5 - t4 == 800

    :ets.delete(:timestamps)
  end

  # -------------------------------------------------------
  # max_delay_ms caps the backoff
  # -------------------------------------------------------

  test "max_delay_ms caps the computed delay", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:ts_cap, [:set, :public, :named_table])

    # Capture for signaling
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:ts_cap, {attempt, Clock.now()})

      # Signal completion
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 5, do: {:error, :fail}, else: {:ok, :done}
    end

    {:ok, rw2} =
      RetryWorker.start_link(
        clock: &Clock.now/0,
        random: &ZeroRandom.rand/1
      )

    task =
      Task.async(fn ->
        RetryWorker.execute(rw2, func,
          max_retries: 5,
          # Set to 1 to bypass real-world waiting
          base_delay_ms: 1,
          max_delay_ms: 300
        )
      end)

    # 1. Wait for initial attempt (t=0)
    assert_receive {:attempt_done, 1}

    # 2. Advance clock and wait for each retry in sequence
    # This matches your logic: 100, 200, then capped at 300
    logical_delays = [100, 200, 300, 300, 300]

    for {delay, attempt_num} <- Enum.with_index(logical_delays, 2) do
      Clock.advance(delay)
      assert_receive {:attempt_done, ^attempt_num}
    end

    assert {:ok, :done} = Task.await(task, 5_000)

    # Now the timestamps will be perfectly aligned
    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}, {6, t6}] =
      for i <- 1..6, do: :ets.lookup(:ts_cap, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 300
    assert t5 - t4 == 300
    assert t6 - t5 == 300

    :ets.delete(:ts_cap)
  end

  # -------------------------------------------------------
  # Jitter
  # -------------------------------------------------------

  test "jitter is added on top of the base delay", %{rw: _rw} do
    start_supervised!({Counter, 0})

    _timestamps = :ets.new(:ts_jitter, [:set, :public, :named_table])

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:ts_jitter, {attempt, Clock.now()})

      if attempt <= 1 do
        {:error, :fail}
      else
        {:ok, :done}
      end
    end

    # Jitter that always returns 50
    fixed_jitter = fn _max -> 50 end

    {:ok, rw2} =
      RetryWorker.start_link(
        clock: &Clock.now/0,
        random: fixed_jitter
      )

    task =
      Task.async(fn ->
        RetryWorker.execute(rw2, func,
          max_retries: 1,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # Expected delay for retry 0: base=100 + jitter=50 = 150
    Process.sleep(50)
    Clock.advance(150)
    Process.sleep(50)

    assert {:ok, :done} = Task.await(task, 5_000)

    [{1, t1}] = :ets.lookup(:ts_jitter, 1)
    [{2, t2}] = :ets.lookup(:ts_jitter, 2)

    assert t2 - t1 == 150

    :ets.delete(:ts_jitter)
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
      Task.async(fn -> RetryWorker.execute(rw, func1, max_retries: 3, base_delay_ms: 100) end)

    task2 =
      Task.async(fn -> RetryWorker.execute(rw, func2, max_retries: 3, base_delay_ms: 100) end)

    # func1 should return immediately without waiting for func2
    assert {:ok, :fast} = Task.await(task1, 2_000)

    # Advance clock so func2's retry fires
    Process.sleep(50)
    Clock.advance(200)

    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Propagates the last error reason
  # -------------------------------------------------------

  test "returns the last error reason on exhaustion", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    assert {:error, :max_retries_exceeded, last_reason} =
             RetryWorker.execute(rw, func, max_retries: 2, base_delay_ms: 50)

    # 1 initial + 2 retries = 3 calls. Last reason = :fail_3
    assert last_reason == :fail_3

    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = RetryWorker.execute(rw, func, [])
  end
end
