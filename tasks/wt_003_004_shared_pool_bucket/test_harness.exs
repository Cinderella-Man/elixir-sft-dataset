defmodule SharedPoolBucketTest do
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

    # Global pool: 10 capacity, 1 token/sec refill
    {:ok, pid} =
      SharedPoolBucket.start_link(
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    %{sp: pid}
  end

  # -------------------------------------------------------
  # Happy path
  # -------------------------------------------------------

  test "both levels drain on a successful acquire", %{sp: sp} do
    # Per-key: 5 capacity, 0.5/sec. Global: 10 capacity, 1/sec.
    assert {:ok, 4, 9} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
    assert {:ok, 3, 8} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
  end

  test "global pool drains across different keys", %{sp: sp} do
    # Alice takes 3, Bob takes 3 — each has their own per-key budget,
    # but the global pool should be at 10 - 3 - 3 = 4
    SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 3)
    SharedPoolBucket.acquire(sp, "bob", 5, 1.0, 3)

    assert {:ok, 4} = SharedPoolBucket.global_level(sp)
  end

  # -------------------------------------------------------
  # Per-key exhaustion
  # -------------------------------------------------------

  test "per-key exhaustion returns :key_empty", %{sp: sp} do
    # Alice drains her per-key (capacity 3, small relative to global 10)
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert {:error, :key_empty, retry_after} =
             SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert is_integer(retry_after)
    assert retry_after > 0

    # Bob is unaffected — global pool still has 7
    assert {:ok, 2, 6} = SharedPoolBucket.acquire(sp, "bob", 3, 1.0)
  end

  test "rejected acquire does not drain either level", %{sp: sp} do
    # Exhaust Alice
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)

    # Reject
    assert {:error, :key_empty, _} = SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    # Global pool must still be at 7 — the rejected acquire must not have drained
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)
  end

  # -------------------------------------------------------
  # Global exhaustion
  # -------------------------------------------------------

  test "global exhaustion returns :global_empty when per-key has capacity", %{sp: sp} do
    # Drain global pool using multiple clients, each with a large per-key cap
    SharedPoolBucket.acquire(sp, "alice", 20, 1.0, 5)
    SharedPoolBucket.acquire(sp, "bob", 20, 1.0, 5)

    # Global pool now at 0, but a new client "carol" with capacity 20 has a full per-key bucket
    assert {:ok, 0} = SharedPoolBucket.global_level(sp)
    assert {:ok, 20} = SharedPoolBucket.key_level(sp, "carol", 20, 1.0)

    assert {:error, :global_empty, retry_after} =
             SharedPoolBucket.acquire(sp, "carol", 20, 1.0)

    assert is_integer(retry_after)
    assert retry_after > 0

    # Rejected → Carol's per-key bucket wasn't drained
    assert {:ok, 20} = SharedPoolBucket.key_level(sp, "carol", 20, 1.0)
  end

  # -------------------------------------------------------
  # Priority: :key_empty takes precedence when both levels are short
  # -------------------------------------------------------

  test "both-empty precedence: per-key reported even when global also empty" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, sp} =
      SharedPoolBucket.start_link(
        global_capacity: 2,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    # Drain both sides simultaneously — alice's 2-token bucket AND the 2-token global
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)

    # Now alice-free = 0 AND global-free = 0.
    assert {:ok, 0} = SharedPoolBucket.key_level(sp, "alice", 2, 1.0)
    assert {:ok, 0} = SharedPoolBucket.global_level(sp)

    # Both levels short — must report :key_empty, not :global_empty.
    assert {:error, :key_empty, _} = SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
  end

  # -------------------------------------------------------
  # Refill on both levels
  # -------------------------------------------------------

  test "both levels refill lazily on subsequent calls", %{sp: sp} do
    # Drain alice's per-key (capacity 3, refill 1/sec)
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)
    # Drain some of global
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "bob", 5, 2.0)

    # Global is now at 4, alice-per-key is at 0
    assert {:ok, 4} = SharedPoolBucket.global_level(sp)

    # Advance 3 seconds.  Per-key refills at 1/sec → +3 tokens → full at 3.
    # Global refills at 1/sec → +3 tokens → up to 7.
    Clock.advance(3_000)

    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "alice", 3, 1.0)
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)
  end

  test "per-key refill caps at per-key capacity", %{sp: sp} do
    # Drain alice (cap 2)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)

    # Idle a very long time — alice must cap at 2, not overflow
    Clock.advance(1_000_000)

    assert {:ok, 2} = SharedPoolBucket.key_level(sp, "alice", 2, 1.0)
  end

  test "global refill caps at global capacity", %{sp: sp} do
    # Drain global partially
    for _ <- 1..5, do: SharedPoolBucket.acquire(sp, "alice", 10, 10.0)

    # Idle a very long time — global caps at 10
    Clock.advance(1_000_000)

    assert {:ok, 10} = SharedPoolBucket.global_level(sp)
  end

  # -------------------------------------------------------
  # Multi-token acquires
  # -------------------------------------------------------

  test "multi-token drain math is correct" do
    # Removed the redundant `start_supervised!({Clock, 0})` here

    {:ok, sp} =
      SharedPoolBucket.start_link(
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 2, 7} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 3)
    assert {:ok, 0, 5} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 2)
  end

  # -------------------------------------------------------
  # key_level for unknown buckets
  # -------------------------------------------------------

  test "key_level for unknown bucket returns capacity", %{sp: sp} do
    assert {:ok, 7} = SharedPoolBucket.key_level(sp, "never_seen", 7, 1.0)
    # Must not have created the bucket
    state = :sys.get_state(sp)
    refute Map.has_key?(state.buckets, "never_seen")
  end

  # -------------------------------------------------------
  # Cleanup
  # -------------------------------------------------------

  test "refilled buckets are dropped in cleanup; global is kept", %{sp: sp} do
    # Touch 50 buckets
    for i <- 1..50, do: SharedPoolBucket.acquire(sp, "k:#{i}", 2, 5.0)

    # Advance long enough for per-key buckets to fully refill
    Clock.advance(10_000)

    send(sp, :cleanup)
    :sys.get_state(sp)

    state = :sys.get_state(sp)
    assert map_size(state.buckets) == 0

    # Global pool is still present — and should have refilled to capacity
    assert {:ok, 10} = SharedPoolBucket.global_level(sp)
  end
end
