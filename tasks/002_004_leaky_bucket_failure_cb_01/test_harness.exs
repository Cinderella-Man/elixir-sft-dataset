defmodule LeakyBucketCircuitBreakerTest do
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
      LeakyBucketCircuitBreaker.start_link(
        name: :test_cb,
        bucket_capacity: 5.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 1.0,
        reset_timeout_ms: 1_000,
        half_open_max_probes: 1,
        clock: &Clock.now/0
      )

    %{cb: :test_cb}
  end

  defp ok_fn, do: fn -> {:ok, :v} end
  defp err_fn, do: fn -> {:error, :f} end

  # -------------------------------------------------------
  # Bucket mechanics
  # -------------------------------------------------------

  test "bucket starts empty", %{cb: cb} do
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "each failure adds failure_weight to bucket", %{cb: cb} do
    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "successes do not add to bucket", %{cb: cb} do
    for _ <- 1..20, do: LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "bucket leaks at leak_rate_per_sec", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 1 second elapsed — leak 1.0 drop
    Clock.advance(1_000)
    assert 2.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # 2 more seconds — leaks to 0
    Clock.advance(2_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "bucket never goes below zero even after long idle", %{cb: cb} do
    Clock.advance(1_000_000)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 1.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "partial-second leak works correctly", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    # 500ms at 1.0 drops/sec = 0.5 leaked
    Clock.advance(500)
    assert 2.5 = LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  # -------------------------------------------------------
  # Tripping behavior — the defining property
  # -------------------------------------------------------

  test "trips when bucket reaches capacity (burst)", %{cb: cb} do
    # 5 failures in quick succession fills the bucket to capacity
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "does not trip when failure rate is outpaced by leak rate", %{cb: cb} do
    # One failure every 2 seconds, leak rate is 1/sec → bucket oscillates ≤ 1.0
    for _ <- 1..20 do
      LeakyBucketCircuitBreaker.call(cb, err_fn())
      Clock.advance(2_000)
    end

    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end

  test "trips on burst even after a long quiet period leaks the bucket empty", %{cb: cb} do
    # Earn some drops, then wait long enough for the bucket to empty
    for _ <- 1..2, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(10_000)
    # Bucket should be at 0 now
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh burst fills the bucket to capacity and trips
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "intermingled successes don't reset the bucket", %{cb: cb} do
    # Unlike a consecutive-count breaker, successes here don't reduce the bucket.
    # 4 failures + a success + 1 more failure should still trip.
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 4.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Custom weights
  # -------------------------------------------------------

  test "failure_weight scales how many drops each failure adds", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :weighted_cb,
        bucket_capacity: 10.0,
        leak_rate_per_sec: 1.0,
        failure_weight: 3.0,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    # 3 failures = 9 drops, still under 10
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert 9.0 == LeakyBucketCircuitBreaker.bucket_level(:weighted_cb)

    # 4th failure → 12 drops, trips
    LeakyBucketCircuitBreaker.call(:weighted_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:weighted_cb)
  end

  test "integer options are coerced to floats", %{cb: _cb} do
    # REMOVED: start_supervised!({Clock, 0})

    # All integer options — should still work
    {:ok, _pid} =
      LeakyBucketCircuitBreaker.start_link(
        name: :int_cb,
        bucket_capacity: 3,
        leak_rate_per_sec: 2,
        failure_weight: 1,
        reset_timeout_ms: 1_000,
        clock: &Clock.now/0
      )

    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(:int_cb, err_fn())
    assert :open == LeakyBucketCircuitBreaker.state(:int_cb)
  end

  # -------------------------------------------------------
  # State transitions
  # -------------------------------------------------------

  test "open state rejects calls without executing", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())

    tracker = self()

    assert {:error, :circuit_open} =
             LeakyBucketCircuitBreaker.call(cb, fn ->
               send(tracker, :was_called)
               {:ok, :v}
             end)

    refute_received :was_called
  end

  test "open → half_open after reset_timeout_ms", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end

  test "probe success → :closed with empty bucket", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:ok, :v} = LeakyBucketCircuitBreaker.call(cb, ok_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    # Fresh bucket — can tolerate some new failures without tripping
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
  end

  test "probe failure → :open with restarted reset timeout", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    Clock.advance(1_000)

    assert {:error, :f} = LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    Clock.advance(500)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
    Clock.advance(500)
    assert :half_open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Exception handling
  # -------------------------------------------------------

  test "raised exceptions count as failures and don't crash the GenServer", %{cb: cb} do
    raise_fn = fn -> raise "boom" end

    assert {:error, %RuntimeError{message: "boom"}} =
             LeakyBucketCircuitBreaker.call(cb, raise_fn)

    pid = Process.whereis(cb)
    assert Process.alive?(pid)

    # 4 more raises fill the bucket and trip
    for _ <- 1..4, do: LeakyBucketCircuitBreaker.call(cb, raise_fn)
    assert :open = LeakyBucketCircuitBreaker.state(cb)
  end

  # -------------------------------------------------------
  # Manual reset
  # -------------------------------------------------------

  test "reset clears the bucket and returns to :closed", %{cb: cb} do
    for _ <- 1..5, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert :open = LeakyBucketCircuitBreaker.state(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end

  test "reset from :closed with partial bucket clears it", %{cb: cb} do
    for _ <- 1..3, do: LeakyBucketCircuitBreaker.call(cb, err_fn())
    assert 3.0 == LeakyBucketCircuitBreaker.bucket_level(cb)

    LeakyBucketCircuitBreaker.reset(cb)
    assert :closed = LeakyBucketCircuitBreaker.state(cb)
    assert 0.0 == LeakyBucketCircuitBreaker.bucket_level(cb)
  end
end
