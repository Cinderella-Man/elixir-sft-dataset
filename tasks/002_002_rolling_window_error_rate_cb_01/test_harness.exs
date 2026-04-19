defmodule RollingRateCircuitBreakerTest do
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

  setup do
    start_supervised!({Clock, 0})

    {:ok, _pid} =
      RollingRateCircuitBreaker.start_link(
        name: :test_cb,
        window_size: 10,
        error_rate_threshold: 0.5,
        min_calls_in_window: 6,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :value} end
  defp err_fn, do: fn -> {:error, :failure} end

  # -------------------------------------------------------
  # Baseline closed behavior
  # -------------------------------------------------------

  test "passes through successes without tripping", %{cb: cb} do
    for _ <- 1..20, do: assert({:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn()))
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "does not trip when error rate is below threshold", %{cb: cb} do
    # 3 errors out of 10 = 30%, below 50% threshold
    for _ <- 1..7, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Rate-based tripping (the defining property)
  # -------------------------------------------------------

  test "trips when error rate reaches threshold and min calls are met", %{cb: cb} do
    # Window: [:ok, :ok, :ok, :error, :error, :error] → 3/6 = 50% ≥ 0.5
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())

    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "does not trip when error rate is high but min_calls not met", %{cb: cb} do
    # 5 errors, 0 successes → 100% error rate, but only 5 calls (min = 6)
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # 6th error now meets min_calls AND threshold → trip
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "alternating success/failure trips once threshold is met", %{cb: cb} do
    # Strict 50/50 alternation — would never trip a consecutive-count breaker.
    for _ <- 1..3 do
      RollingRateCircuitBreaker.call(cb, ok_fn())
      RollingRateCircuitBreaker.call(cb, err_fn())
    end

    # Window: 3 errors / 6 total = 50% ≥ 0.5, min_calls met → trip
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  test "rolling window evicts old outcomes and can un-trip risk as errors age out", %{cb: cb} do
    # Fill window with 10 successes
    for _ <- 1..10, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Adding 4 errors: window is [4 errors, 6 successes] = 4/10 = 40%, still closed
    for _ <- 1..4, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # One more error: now [5 errors, 5 successes] = 50%, trips.
    RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Open / half-open transitions
  # -------------------------------------------------------

  test "open state rejects calls without executing the function", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             RollingRateCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :wat}
             end)

    refute_received :was_called
  end

  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end

  test "half_open probe success → closed with empty window", %{cb: cb} do
    # Trip, then wait to half-open
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    # Successful probe → closed
    assert {:ok, :value} = RollingRateCircuitBreaker.call(cb, ok_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Old outcomes are wiped — 3 fresh errors shouldn't trip (below min_calls)
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end

  test "half_open probe failure → open and restarts reset timeout", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = RollingRateCircuitBreaker.state(cb)

    assert {:error, :failure} = RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    # Reset timeout must restart, not carry over
    Clock.advance(500)
    assert :open = RollingRateCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :half_open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             RollingRateCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 6 raises should meet min_calls at 100% error rate → trip
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, raise_fn)
    assert :open = RollingRateCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset returns to closed from any state and clears the window", %{cb: cb} do
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..3, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :open = RollingRateCircuitBreaker.state(cb)

    RollingRateCircuitBreaker.reset(cb)
    assert :closed = RollingRateCircuitBreaker.state(cb)

    # Window should be empty — a new burst of errors shouldn't re-trip until
    # min_calls is met again.
    for _ <- 1..5, do: RollingRateCircuitBreaker.call(cb, err_fn())
    assert :closed = RollingRateCircuitBreaker.state(cb)
  end
end
