# Make this test suite pass

Below is a complete, self-contained ExUnit test suite. Treat it as the
full specification: write the module (or modules) under test so that
every test passes. Use only what the tests themselves require — the
standard library and OTP unless the suite references anything else.
Follow idiomatic Elixir house style (`@moduledoc`, `@doc` + `@spec` on
the public API, no compiler warnings).

## The test suite

```elixir
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

  # -------------------------------------------------------
  # Helpers for the default-configuration tests below
  # -------------------------------------------------------

  # Starts an extra breaker under a process-unique name, defaulting every
  # option except the injected clock (so documented defaults are exercised).
  defp start_cb(opts) do
    name = :"prcb_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, _pid} =
      ProgressiveRecoveryCircuitBreaker.start_link(
        Keyword.merge([name: name, clock: &Clock.now/0], opts)
      )

    name
  end

  defp repeat_call(cb, n, func) do
    for _ <- 1..n, do: ProgressiveRecoveryCircuitBreaker.call(cb, func)
    :ok
  end

  # Default breaker (threshold 5, reset 30_000ms, 1 probe) driven into
  # :recovering at stage 0 of the default ladder.
  defp default_cb_in_recovering do
    cb = start_cb([])
    repeat_call(cb, 5, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
    Clock.advance(30_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
    cb
  end

  # -------------------------------------------------------
  # Documented defaults
  # -------------------------------------------------------

  test "default failure_threshold trips only on the 5th consecutive failure" do
    cb = start_cb([])

    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default reset timeout is 30_000ms and the default single probe is allowed" do
    cb = start_cb([])
    repeat_call(cb, 5, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(29_999)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    Clock.advance(1)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # half_open_max_probes defaults to 1 — the probe must be let through.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default stage 0 tolerates zero failures" do
    cb = default_cb_in_recovering()

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default ladder: stage 0 needs 5 calls, stage 1 needs 15 with 1 failure tolerated" do
    cb = default_cb_in_recovering()

    # 4 of the 5 calls required by stage 0 — stage not cleared yet.
    repeat_call(cb, 4, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 5th call clears stage 0 → stage 1 ({15, 1}).
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 tolerates exactly 1 failure (a stage-0 zero tolerance here
    # would have reopened the circuit).
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 1 failure + 13 successes = 14 of the 15 calls stage 1 requires.
    repeat_call(cb, 13, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 15th call is a 2nd failure → exceeds stage 1 tolerance → :open.
    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "default final stage needs 30 calls and tolerates 2 failures before closing" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 ({30, 2}): two failures are within tolerance.
    repeat_call(cb, 2, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # 2 failures + 27 successes = 29 of the 30 required calls — not closed yet.
    repeat_call(cb, 27, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # The 30th call clears the final stage → :closed.
    assert {:ok, :v} = ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "closing via full recovery leaves a zeroed consecutive failure count" do
    cb = default_cb_in_recovering()

    repeat_call(cb, 5, ok_fn())
    repeat_call(cb, 15, ok_fn())
    repeat_call(cb, 30, ok_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    # A full 5 consecutive failures must be needed again, not fewer.
    repeat_call(cb, 4, err_fn())
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    assert {:error, :f} = ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Probe budget and outcome classification
  # -------------------------------------------------------

  test "half-open lets no calls through when the probe budget is zero" do
    cb =
      start_cb(
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 0,
        recovery_stages: [{3, 0}]
      )

    repeat_call(cb, 3, err_fn())
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)

    tracker = self()

    assert {:error, :circuit_open} =
             ProgressiveRecoveryCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "an unexpected return shape counts as a failure in closed state" do
    cb =
      start_cb(
        failure_threshold: 3,
        reset_timeout_ms: 1_000,
        recovery_stages: [{3, 0}]
      )

    repeat_call(cb, 2, fn -> :not_a_result end)
    assert :closed = ProgressiveRecoveryCircuitBreaker.state(cb)

    ProgressiveRecoveryCircuitBreaker.call(cb, fn -> :not_a_result end)
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "stage failure counter resets when advancing to the next stage", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0}: three clean successes → advance to stage 1.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 1 {5, 1}: one tolerated failure then four successes → 5 calls → stage 2.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    for _ <- 1..4, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 2 {10, 2}: two failures must be tolerated afresh. If the stage-1
    # failure carried over, 1 + 2 = 3 > 2 would reopen the circuit.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)
  end

  test "re-probe after reopening from a later stage restarts recovery at stage 0", %{cb: cb} do
    trip_to_half_open(cb)
    # Probe success → recovering stage 0.
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())

    # Clear stage 0 {3, 0} → now in stage 1 {5, 1}.
    for _ <- 1..3, do: ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Exceed stage 1 tolerance (2 failures) → :open, from a deep stage.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Back to half-open; a fresh probe success must restart recovery at stage 0.
    Clock.advance(1_000)
    assert :half_open = ProgressiveRecoveryCircuitBreaker.state(cb)
    ProgressiveRecoveryCircuitBreaker.call(cb, ok_fn())
    assert :recovering = ProgressiveRecoveryCircuitBreaker.state(cb)

    # Stage 0 tolerates zero failures — a single failure reopens. If recovery
    # had resumed at stage 1 (tolerates 1), this failure would be tolerated.
    ProgressiveRecoveryCircuitBreaker.call(cb, err_fn())
    assert :open = ProgressiveRecoveryCircuitBreaker.state(cb)
  end
end
```

Give me the complete implementation in a single file — the module(s)
alone, not the tests.
