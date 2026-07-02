defmodule LeakyBucketTest do
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
    # Start fresh clock at time 0 for each test
    start_supervised!({Clock, 0})

    {:ok, pid} =
      LeakyBucket.start_link(
        clock: &Clock.now/0,
        # disable auto-cleanup in tests
        cleanup_interval_ms: :infinity
      )

    %{lb: pid}
  end

  # -------------------------------------------------------
  # Basic acquire / reject
  # -------------------------------------------------------

  test "new bucket starts full at capacity", %{lb: lb} do
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 1)
  end

  test "drains tokens one at a time", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 3, 1)
  end

  test "rejects when bucket is empty", %{lb: lb} do
    for _ <- 1..3, do: LeakyBucket.acquire(lb, "b", 3, 1)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 3, 1)

    assert is_integer(retry_after)
    assert retry_after > 0
  end

  # -------------------------------------------------------
  # Multi-token acquire
  # -------------------------------------------------------

  test "can acquire multiple tokens at once", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 5, 1, 3)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 5, 1, 2)
  end

  test "rejects multi-token acquire when not enough tokens", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 5, 1, 3)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 1, 3)

    assert is_integer(retry_after)
    assert retry_after > 0
  end

  # -------------------------------------------------------
  # Refill behaviour
  # -------------------------------------------------------

  test "tokens refill based on elapsed time", %{lb: lb} do
    # Capacity 10, refill rate 5 tokens/sec. Drain all 10.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 5)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 10, 5)

    # Advance 1 second => 5 tokens refilled
    Clock.advance(1_000)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 10, 5)
  end

  test "partial refill works correctly", %{lb: lb} do
    # Capacity 10, refill rate 10 tokens/sec. Drain all.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 10)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 10, 10)

    # Advance 500ms => 5 tokens refilled
    Clock.advance(500)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 10, 10)
  end

  test "bucket never exceeds capacity after long idle", %{lb: lb} do
    # Drain 1 token from a capacity-5 bucket
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 10)

    # Advance a very long time
    Clock.advance(1_000_000)

    # Bucket should be full at capacity, not over
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 10)
  end

  test "refill allows requests again after draining", %{lb: lb} do
    # Capacity 2, refill 1/sec. Drain it.
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 2, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Advance 1 second => 1 token refilled
    Clock.advance(1_000)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Empty again
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Advance another second => 1 more token
    Clock.advance(1_000)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)
  end

  # -------------------------------------------------------
  # retry_after accuracy
  # -------------------------------------------------------

  test "retry_after tells how long until enough tokens refill", %{lb: lb} do
    # Capacity 5, refill 2/sec. Drain all.
    for _ <- 1..5, do: LeakyBucket.acquire(lb, "b", 5, 2)

    # Need 1 token at 2/sec => 500ms
    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 2, 1)

    assert retry_after >= 400 and retry_after <= 600
  end

  test "retry_after accounts for multi-token request", %{lb: lb} do
    # Capacity 10, refill 2/sec. Drain all.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 2)

    # Need 4 tokens at 2/sec => 2000ms
    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 10, 2, 4)

    assert retry_after >= 1_800 and retry_after <= 2_200
  end

  test "retry_after accounts for partial token balance", %{lb: lb} do
    # Capacity 5, refill 2/sec. Drain all.
    for _ <- 1..5, do: LeakyBucket.acquire(lb, "b", 5, 2)

    # Advance 200ms => 0.4 tokens refilled (not enough for 1)
    Clock.advance(200)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 2, 1)

    # Need 0.6 more tokens at 2/sec => 300ms
    assert retry_after >= 200 and retry_after <= 400
  end

  # -------------------------------------------------------
  # Bucket independence
  # -------------------------------------------------------

  test "different bucket names are completely independent", %{lb: lb} do
    # Exhaust bucket "a"
    for _ <- 1..3, do: LeakyBucket.acquire(lb, "a", 3, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "a", 3, 1)

    # Bucket "b" should be unaffected
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 3, 1)
  end

  test "interleaved operations on multiple buckets", %{lb: lb} do
    assert {:ok, 1} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "y", 5, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 3} = LeakyBucket.acquire(lb, "y", 5, 1)

    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 2} = LeakyBucket.acquire(lb, "y", 5, 1)
  end

  # -------------------------------------------------------
  # Edge cases
  # -------------------------------------------------------

  test "capacity of 1 allows exactly one acquire", %{lb: lb} do
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 1, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 1, 1)
  end

  test "works with very high refill rate", %{lb: lb} do
    # Capacity 100, refill 1000/sec. Drain all.
    for _ <- 1..100, do: LeakyBucket.acquire(lb, "b", 100, 1_000)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 100, 1_000)

    # 100ms => 100 tokens refilled (capped at capacity)
    Clock.advance(100)
    assert {:ok, 99} = LeakyBucket.acquire(lb, "b", 100, 1_000)
  end

  test "requesting more tokens than capacity always fails", %{lb: lb} do
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 5, 1, 6)
  end

  # -------------------------------------------------------
  # Cleanup (memory leak prevention)
  # -------------------------------------------------------

  test "stale buckets are cleaned up and don't accumulate", %{lb: lb} do
    # Create entries for 100 different buckets
    for i <- 1..100 do
      LeakyBucket.acquire(lb, "bucket:#{i}", 5, 1)
    end

    # Advance past the default cleanup TTL (300_000ms = 5 minutes)
    Clock.advance(300_001)

    # Trigger cleanup manually via a message
    send(lb, :cleanup)
    # Give it a moment to process
    :sys.get_state(lb)

    # Internal state should have no bucket entries
    state = :sys.get_state(lb)
    assert map_size(state.buckets) == 0

    # New request for a cleaned-up bucket should start fresh at capacity
    assert {:ok, 4} = LeakyBucket.acquire(lb, "bucket:1", 5, 1)
  end

  test "recently accessed buckets survive cleanup", %{lb: lb} do
    LeakyBucket.acquire(lb, "active", 5, 1)
    LeakyBucket.acquire(lb, "stale", 5, 1)

    # Advance 200 seconds
    Clock.advance(200_000)

    # Touch "active" again so its last-access is recent
    LeakyBucket.acquire(lb, "active", 5, 1)

    # Advance another 150 seconds (total 350s for "stale", 150s for "active")
    Clock.advance(150_000)

    # Trigger cleanup (TTL is 300_000ms)
    send(lb, :cleanup)
    :sys.get_state(lb)

    state = :sys.get_state(lb)
    assert Map.has_key?(state.buckets, "active")
    refute Map.has_key?(state.buckets, "stale")
  end
end
