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

  # =======================================================
  # Added coverage: defaults, backoff arithmetic, jitter source
  # =======================================================

  # A jitter source that records every `delay` it is handed and cancels the
  # wait (jitter = -delay, so `delay + jitter == 0`), letting us read the exact
  # delay sequence without spending wall-clock time on backoff.
  defp recording_random do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    random = fn delay ->
      Agent.update(agent, &[delay | &1])
      -delay
    end

    {agent, random}
  end

  defp recorded_delays(agent), do: agent |> Agent.get(& &1) |> Enum.reverse()

  defp always_fails, do: fn -> {:error, :boom} end

  defp elapsed_ms(fun) do
    started = System.monotonic_time(:millisecond)
    fun.()
    System.monotonic_time(:millisecond) - started
  end

  # `max_retries` defaults to 3, so `func` may run at most 3 + 1 = 4 times.
  test "default max_retries of 3 allows exactly four invocations" do
    worker = start_supervised!({TimeoutRetryWorker, [random: fn _max -> 0 end]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(calls, & &1) == 4
    Agent.stop(calls)
  end

  # Delay for retry N is min(base_delay_ms * 2^(N-1), max_delay_ms), and
  # base_delay_ms defaults to 100: retries 1, 2, 3 use 100, 200, 400.
  test "default base_delay_ms of 100 doubles for each successive retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [100, 200, 400]
    Agent.stop(agent)
  end

  # The jitter function is called with the computed delay whenever the delay is
  # positive; max_delay_ms caps the delay, here at 1 for every retry.
  test "jitter function is called with the capped delay on every positive-delay retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [1, 1, 1]
    Agent.stop(agent)
  end

  # A zero delay must not consult the jitter function at all.
  test "zero delay never calls the jitter function yet still retries" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 100,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == []
    assert Agent.get(calls, & &1) == 4

    Agent.stop(calls)
    Agent.stop(agent)
  end

  # With a zero delay the jitter is 0, so the total wait is 0: a long chain of
  # zero-delay retries must cost no more wall-clock than the same chain whose
  # jitter cancels the delay out to a zero wait.
  test "zero delay waits nothing rather than a millisecond per retry" do
    retries = 400
    worker = start_supervised!({TimeoutRetryWorker, [random: fn delay -> -delay end]})

    cancelled = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    zeroed = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    baseline_ms = elapsed_ms(cancelled)
    zero_delay_ms = elapsed_ms(zeroed)

    # A 1 ms wait per retry would add ~400 ms over the zero-wait baseline.
    assert zero_delay_ms - baseline_ms < 200
  end

  # The default jitter source yields values in 0..max-1, so a delay of 1 admits
  # only jitter 0: each retry waits exactly 1 ms — never 0 ms, never 2 ms.
  test "default jitter source keeps a one-millisecond delay at a one-millisecond wait" do
    retries = 300
    worker = start_supervised!({TimeoutRetryWorker, []})

    overhead = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 0,
                 max_delay_ms: 0,
                 attempt_timeout_ms: 1_000
               )
    end

    jittered = fn ->
      assert {:error, :max_retries_exceeded, :boom} =
               TimeoutRetryWorker.execute(worker, always_fails(),
                 max_retries: retries,
                 base_delay_ms: 1,
                 max_delay_ms: 1,
                 attempt_timeout_ms: 1_000
               )
    end

    overhead_ms = elapsed_ms(overhead)
    waited_ms = elapsed_ms(jittered) - overhead_ms

    # 300 retries x exactly 1 ms of wait, minus the no-wait overhead baseline.
    assert waited_ms >= 100
    assert waited_ms <= 560
  end

  test "abnormal task exit yields task_crashed reason on the final exhausted attempt", %{rw: rw} do
    func = fn -> exit(:kaboom) end

    assert {:error, :max_retries_exceeded, {:task_crashed, :kaboom}} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 0,
               attempt_timeout_ms: 1_000
             )
  end

  test "abnormal task exit is retryable so a later attempt can still succeed", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n == 1, do: exit(:kaboom), else: {:ok, :recovered}
    end

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    Agent.stop(agent)
  end

  test "registers under the :name option and serves calls addressed by that name" do
    {:ok, _pid} =
      TimeoutRetryWorker.start_link(
        name: :trw_named_worker,
        random: &ZeroRandom.rand/1
      )

    assert {:ok, :via_name} =
             TimeoutRetryWorker.execute(:trw_named_worker, fn -> {:ok, :via_name} end,
               max_retries: 0
             )
  end

  test "start_link with no arguments starts a usable worker" do
    assert {:ok, pid} = TimeoutRetryWorker.start_link()

    assert {:ok, :no_arg} =
             TimeoutRetryWorker.execute(pid, fn -> {:ok, :no_arg} end, max_retries: 0)
  end

  test "execute called with only server and func uses the default option set", %{rw: rw} do
    assert {:ok, :two_arg} = TimeoutRetryWorker.execute(rw, fn -> {:ok, :two_arg} end)
  end

  test "re-running execute on the same server restarts attempt counting from zero", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(agent, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.update(agent, fn _ -> 0 end)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.stop(agent)
  end
end
