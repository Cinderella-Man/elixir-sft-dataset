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
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    assert {:error, :max_retries_exceeded, last_reason} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 5_000
             )

    assert last_reason == :fail_3

    Agent.stop(agent)
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
