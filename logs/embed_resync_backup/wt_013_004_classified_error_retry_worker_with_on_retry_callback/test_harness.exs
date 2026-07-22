defmodule ClassifiedRetryWorkerTest do
  use ExUnit.Case, async: false

  # --- Fake clock ---

  defmodule Clock do
    use Agent

    def start_link(initial \\ 0) do
      Agent.start_link(fn -> initial end, name: __MODULE__)
    end

    def now, do: Agent.get(__MODULE__, & &1)
    def advance(ms), do: Agent.update(__MODULE__, &(&1 + ms))
  end

  # --- Fake random that always returns 0 ---

  defmodule ZeroRandom do
    def rand(_max), do: 0
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

  # --- Retry log recorder ---

  defmodule RetryLog do
    use Agent

    def start_link(_opts \\ []) do
      Agent.start_link(fn -> [] end, name: __MODULE__)
    end

    def record(attempt, reason, delay) do
      Agent.update(__MODULE__, &(&1 ++ [{attempt, reason, delay}]))
    end

    def entries, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!({Clock, 0})

    {:ok, pid} =
      ClassifiedRetryWorker.start_link(
        clock: &Clock.now/0,
        random: &ZeroRandom.rand/1
      )

    %{rw: pid}
  end

  # -------------------------------------------------------
  # Immediate success
  # -------------------------------------------------------

  test "returns immediately when function succeeds on first try", %{rw: rw} do
    func = fn -> {:ok, 42} end

    assert {:ok, 42} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)
  end

  test "does not retry when function succeeds on first try", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:ok, :yep}
    end

    assert {:ok, :yep} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Permanent error — no retry
  # -------------------------------------------------------

  test "permanent error returns immediately without retry", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :permanent, :invalid_input}
    end

    assert {:error, :permanent, :invalid_input} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    # Only called once — no retries
    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Transient errors — retries then succeeds
  # -------------------------------------------------------

  test "retries transient errors and succeeds", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :service_unavailable}
      else
        {:ok, :recovered}
      end
    end

    assert {:ok, :recovered} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 5, base_delay_ms: 100)

    assert Counter.get() == 4
  end

  test "succeeds on the very last retry", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :timeout}
      else
        {:ok, :last_chance}
      end
    end

    assert {:ok, :last_chance} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    assert Counter.get() == 4
  end

  # -------------------------------------------------------
  # Transient errors — retries exhausted
  # -------------------------------------------------------

  test "returns retries_exhausted when all retries fail with transient", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :transient, :still_down}
    end

    assert {:error, :retries_exhausted, :still_down} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 3, base_delay_ms: 100)

    # 1 initial + 3 retries = 4 calls
    assert Counter.get() == 4
  end

  test "max_retries of 0 means no retries for transient errors", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      Counter.increment_and_get()
      {:error, :transient, :boom}
    end

    assert {:error, :retries_exhausted, :boom} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 0, base_delay_ms: 100)

    assert Counter.get() == 1
  end

  # -------------------------------------------------------
  # Transient then permanent — stops immediately
  # -------------------------------------------------------

  test "permanent error after transient errors stops retries immediately", %{rw: rw} do
    start_supervised!({Counter, 0})

    func = fn ->
      attempt = Counter.increment_and_get()

      case attempt do
        1 -> {:error, :transient, :flaky}
        2 -> {:error, :transient, :flaky}
        3 -> {:error, :permanent, :auth_revoked}
        _ -> {:ok, :should_not_reach}
      end
    end

    assert {:error, :permanent, :auth_revoked} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 10, base_delay_ms: 100)

    # Stopped at attempt 3 even though 10 retries were allowed
    assert Counter.get() == 3
  end

  # -------------------------------------------------------
  # on_retry callback
  # -------------------------------------------------------

  test "on_retry callback is invoked before each retry", %{rw: rw} do
    start_supervised!({Counter, 0})
    start_supervised!({RetryLog, []})

    func = fn ->
      attempt = Counter.increment_and_get()

      if attempt <= 3 do
        {:error, :transient, :"fail_#{attempt}"}
      else
        {:ok, :done}
      end
    end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:ok, :done} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 5,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    entries = RetryLog.entries()
    assert length(entries) == 3

    # With ZeroRandom (jitter=0), delays are: 100, 200, 400
    assert Enum.at(entries, 0) == {1, :fail_1, 100}
    assert Enum.at(entries, 1) == {2, :fail_2, 200}
    assert Enum.at(entries, 2) == {3, :fail_3, 400}
  end

  test "on_retry is not called when function succeeds on first try", %{rw: rw} do
    start_supervised!({RetryLog, []})

    func = fn -> {:ok, :immediate} end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:ok, :immediate} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    assert RetryLog.entries() == []
  end

  test "on_retry is not called on permanent error", %{rw: rw} do
    start_supervised!({RetryLog, []})

    func = fn -> {:error, :permanent, :fatal} end

    on_retry = fn attempt, reason, delay ->
      RetryLog.record(attempt, reason, delay)
    end

    assert {:error, :permanent, :fatal} =
             ClassifiedRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 100,
               on_retry: on_retry
             )

    assert RetryLog.entries() == []
  end

  # -------------------------------------------------------
  # Exponential backoff delays (with zero jitter)
  # -------------------------------------------------------

  test "delays grow exponentially with zero jitter", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:timestamps_v3, [:set, :public, :named_table])
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:timestamps_v3, {attempt, Clock.now()})
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 4,
        do: {:error, :transient, :fail},
        else: {:ok, :done}
    end

    {:ok, rw2} =
      ClassifiedRetryWorker.start_link(clock: &Clock.now/0, random: &ZeroRandom.rand/1)

    task =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw2, func, max_retries: 4, base_delay_ms: 1)
      end)

    assert_receive {:attempt_done, 1}
    Clock.advance(100)
    assert_receive {:attempt_done, 2}
    Clock.advance(200)
    assert_receive {:attempt_done, 3}
    Clock.advance(400)
    assert_receive {:attempt_done, 4}
    Clock.advance(800)
    assert_receive {:attempt_done, 5}

    assert {:ok, :done} = Task.await(task)

    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}] =
      for i <- 1..5, do: :ets.lookup(:timestamps_v3, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 400
    assert t5 - t4 == 800

    :ets.delete(:timestamps_v3)
  end

  # -------------------------------------------------------
  # max_delay_ms caps the backoff
  # -------------------------------------------------------

  test "max_delay_ms caps the computed delay", %{rw: _rw} do
    start_supervised!({Counter, 0})
    _timestamps = :ets.new(:ts_cap_v3, [:set, :public, :named_table])
    test_pid = self()

    func = fn ->
      attempt = Counter.increment_and_get()
      :ets.insert(:ts_cap_v3, {attempt, Clock.now()})
      send(test_pid, {:attempt_done, attempt})

      if attempt <= 5,
        do: {:error, :transient, :fail},
        else: {:ok, :done}
    end

    {:ok, rw2} =
      ClassifiedRetryWorker.start_link(clock: &Clock.now/0, random: &ZeroRandom.rand/1)

    task =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw2, func,
          max_retries: 5,
          base_delay_ms: 1,
          max_delay_ms: 300
        )
      end)

    assert_receive {:attempt_done, 1}

    logical_delays = [100, 200, 300, 300, 300]

    for {delay, attempt_num} <- Enum.with_index(logical_delays, 2) do
      Clock.advance(delay)
      assert_receive {:attempt_done, ^attempt_num}
    end

    assert {:ok, :done} = Task.await(task, 5_000)

    [{1, t1}, {2, t2}, {3, t3}, {4, t4}, {5, t5}, {6, t6}] =
      for i <- 1..6, do: :ets.lookup(:ts_cap_v3, i) |> List.first()

    assert t2 - t1 == 100
    assert t3 - t2 == 200
    assert t4 - t3 == 300
    assert t5 - t4 == 300
    assert t6 - t5 == 300

    :ets.delete(:ts_cap_v3)
  end

  # -------------------------------------------------------
  # Concurrent executions are independent
  # -------------------------------------------------------

  test "multiple concurrent executions don't block each other", %{rw: rw} do
    func1 = fn -> {:ok, :fast} end

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if n <= 1,
        do: {:error, :transient, :not_yet},
        else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw, func1, max_retries: 3, base_delay_ms: 100)
      end)

    task2 =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw, func2, max_retries: 3, base_delay_ms: 100)
      end)

    assert {:ok, :fast} = Task.await(task1, 2_000)

    Process.sleep(50)
    Clock.advance(200)

    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Last transient reason propagated
  # -------------------------------------------------------

  test "returns the last transient error reason on exhaustion", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :transient, :"fail_#{n}"}
    end

    assert {:error, :retries_exhausted, last_reason} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 2, base_delay_ms: 50)

    assert last_reason == :fail_3

    Agent.stop(agent)
  end

  # -------------------------------------------------------
  # Default options
  # -------------------------------------------------------

  test "uses default options when not specified", %{rw: rw} do
    func = fn -> {:ok, :defaults_work} end
    assert {:ok, :defaults_work} = ClassifiedRetryWorker.execute(rw, func, [])
  end
end
