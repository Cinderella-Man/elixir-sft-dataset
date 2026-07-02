defmodule ProgressiveRecoveryCircuitBreakerTest do
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

    # Smaller stage numbers for test tractability
    {:ok, _pid} =
      ProgressiveRecoveryCircuitBreaker.start_link(
        name: :test_cb,
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        recovery_stages: [{3, 0}, {5, 1}, {10, 2}],
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :v} end
  defp err_fn, do: fn -> {:error, :f} end

  # Trips the breaker and advances time so it's in :half_open.
  defp trip_to_half_open(cb) do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Baseline closed behavior (matches standard CB)
  # -------------------------------------------------------

  test "passes through successes in closed state", %{cb: cb} do
    for _ <- 1..10, do: assert({:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn()))
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "trips on threshold consecutive failures", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "success between failures resets consecutive failure count", %{cb: cb} do
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    # Non-consecutive — reset
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end

  # -------------------------------------------------------
  # The defining behavior: probe success → :recovering (not :closed)
  # -------------------------------------------------------

  test "successful probe enters :recovering, not :closed directly", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    trip_to_half_open(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer restarts from the new :open transition, not from original
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Progressive recovery path — the full ladder
  # -------------------------------------------------------

  test "clears every recovery stage → :closed", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe → recovering (stage 0)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0: 3 calls, 0 failures tolerated
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1: 5 calls, 1 failure tolerated
    for _ <- 1..5, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2: 10 calls, 2 failures tolerated → final stage → :closed
    for _ <- 1..10, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "failure within stage tolerance stays in stage", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 (3 calls, 0 failures)
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Now in stage 1: 5 calls, 1 failure tolerated
    # 2 successes + 1 failure = stage_calls=3, stage_failures=1, still under limit
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 more successes: stage_calls=5, advance to stage 2
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "failure in stage 0 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 0 tolerates 0 failures — a single error bounces back to :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "second failure in stage 1 exceeds tolerance → :open", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Clear stage 0
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Stage 1: 1 failure is fine, 2 is too many
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "reopening from :recovering restarts reset timeout", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Trigger recovery failure → :open
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Reset timer must be fresh (1s), not carried over
    Clock.advance(500)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exception is a failure and doesn't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 2 more raises (threshold=3) → trip
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, raise_fn)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "raised exception in :recovering counts as a stage failure", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Stage 0: zero tolerance

    assert {:error, %RuntimeError{}} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn -> raise "boom" end)

    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset returns to :closed from :open", %{cb: cb} do
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "reset returns to :closed from :recovering and clears stage counters", %{cb: cb} do
    trip_to_half_open(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    # Advance into stage 1 with some progress
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.reset(cb)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # After reset, failure count should be fresh — need full 3 consecutive
    # failures to trip again (not some leftover count).
    for _ <- 1..2, do: ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end
end
