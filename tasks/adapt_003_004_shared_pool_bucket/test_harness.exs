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

    # Querying does not define the bucket: asking again with a different
    # capacity still reports a fresh, full bucket at that capacity (a bucket
    # created by the first query would have been pinned at 7 tokens).
    assert {:ok, 100} = SharedPoolBucket.key_level(sp, "never_seen", 100, 1.0)
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

    # Global pool survives the sweep and has refilled to capacity.  This
    # synchronous read also waits until the sweep has been processed.
    assert {:ok, 10} = SharedPoolBucket.global_level(sp)

    # Every swept bucket is gone: re-querying under a larger capacity reports a
    # fresh, full bucket instead of the 2-token balance a retained bucket
    # would still carry.
    for i <- 1..50 do
      assert {:ok, 50} = SharedPoolBucket.key_level(sp, "k:#{i}", 50, 1.0)
    end
  end

  # -------------------------------------------------------
  # Documented math, pinned exactly through the public API
  # (injected clock; no reach-ins)
  # -------------------------------------------------------

  test "retry_after for :key_empty is ceil(deficit * 1000 / rate), exactly", %{sp: sp} do
    # cap 2, rate 2.0: drain 1 -> free 1; asking for 2 leaves deficit 1.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "ra1", 2, 2.0, 1)
    assert {:error, :key_empty, 500} = SharedPoolBucket.acquire(sp, "ra1", 2, 2.0, 2)

    # Non-integer quotient rounds UP: deficit 1 at 3.0 tokens/s -> 334 ms.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "ra2", 1, 3.0, 1)
    assert {:error, :key_empty, 334} = SharedPoolBucket.acquire(sp, "ra2", 1, 3.0, 1)
  end

  test "retry_after for :global_empty reflects the global shortage, exactly", %{sp: sp} do
    # Per-key never blocks (cap 100); global 10 - 8 = 2 free, deficit 3 at
    # 1.0 tokens/s -> exactly 3000 ms.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "g1", 100, 100.0, 8)
    assert {:error, :global_empty, 3000} = SharedPoolBucket.acquire(sp, "g2", 100, 100.0, 5)
  end

  test "global refill follows elapsed * rate / 1000 with the documented floor", %{sp: sp} do
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "gr", 100, 100.0, 6)

    # 4 free + 1998 ms * 1.0/s = 5.998 -> floor 5 (a /1000 or arithmetic slip
    # lands on 6 or refills to capacity).
    Clock.advance(1_998)
    assert {:ok, 5} = SharedPoolBucket.global_level(sp)
  end

  test "per-key refill follows elapsed * rate / 1000 with the documented floor", %{sp: sp} do
    # Fresh bucket starts exactly full: cap 2 - 2 = 0 remaining.
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "kr0", 2, 1.0, 2)

    # cap 5: free 2 after draining 3; +1998 ms at 1.0/s = 3.998 -> floor 3.
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "kr", 5, 1.0, 3)
    Clock.advance(1_998)
    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "kr", 5, 1.0)
  end

  test "non-positive capacity, rate or tokens match no clause; capacity 1 is legal", %{sp: sp} do
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "v1", 1, 1.0, 1)
    assert {:ok, _} = SharedPoolBucket.key_level(sp, "v1", 1, 1.0)

    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 0, 1.0, 1) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 1, 0.0, 1) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.acquire(sp, "v2", 1, 1.0, 0) end
    assert_raise FunctionClauseError, fn -> SharedPoolBucket.key_level(sp, "v2", 0, 1.0) end
  end

  test "cleanup keeps a not-yet-full bucket with its projected balance intact", %{sp: sp} do
    # cap 4: free 2 after draining 2; +1998 ms at 1.0/s projects 3.998 < 4,
    # so the sweep must KEEP the bucket (a projection slip refills it to
    # capacity and drops it, making key_level report a fresh 4).
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "cl", 4, 1.0, 2)
    Clock.advance(1_998)
    send(sp, :cleanup)

    assert {:ok, 3} = SharedPoolBucket.key_level(sp, "cl", 4, 1.0)
  end

  test "cleanup projects from the bucket's own last update at its own rate", %{sp: sp} do
    # Bucket born at t=500 with rate 3.0 — a projection using the wrong
    # elapsed origin refills it past capacity and drops it (fresh 9), and one
    # using the wrong rate arithmetic lands on floor 4 instead of 6.
    Clock.advance(500)
    assert {:ok, _, _} = SharedPoolBucket.acquire(sp, "cl3", 9, 3.0, 5)

    # +700 ms at 3.0/s: 4 + 2.1 = 6.1 < 9 -> kept; key_level floors to 6.
    Clock.advance(700)
    send(sp, :cleanup)
    assert {:ok, 6} = SharedPoolBucket.key_level(sp, "cl3", 9, 3.0)
  end

  test "sub-millisecond key shortage still reports a 1 ms retry_after", %{sp: sp} do
    # cap 1, rate 2000/s: drain the single token, leaving free 0.
    assert {:ok, 0, _} = SharedPoolBucket.acquire(sp, "fast", 1, 2000.0, 1)

    # Deficit 1 at 2000 tokens/s needs 0.5 ms — sub-millisecond — must floor up to 1.
    assert {:error, :key_empty, 1} = SharedPoolBucket.acquire(sp, "fast", 1, 2000.0, 1)
  end

  test "invalid acquire neither drains an existing bucket nor creates a new one", %{sp: sp} do
    # Establish a known drained state on an existing bucket.
    assert {:ok, 4, 9} = SharedPoolBucket.acquire(sp, "alice", 5, 1.0)

    # Invalid tokens raises and must not touch any existing state.
    assert_raise FunctionClauseError, fn ->
      SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 0)
    end

    # Existing bucket untouched (still 4, not drained further); global untouched.
    assert {:ok, 4} = SharedPoolBucket.key_level(sp, "alice", 5, 1.0)
    assert {:ok, 9} = SharedPoolBucket.global_level(sp)

    # A never-seen bucket targeted by an invalid call must not be created: a later
    # query with a different capacity still reports a fresh, full bucket.
    assert_raise FunctionClauseError, fn ->
      SharedPoolBucket.acquire(sp, "ghost", 0, 1.0, 1)
    end

    assert {:ok, 100} = SharedPoolBucket.key_level(sp, "ghost", 100, 1.0)
  end

  test "global_empty rejection leaves the global pool balance untouched", %{sp: sp} do
    # Per-key never blocks (cap 100). Drain global from 10 down to 2.
    assert {:ok, _, 2} = SharedPoolBucket.acquire(sp, "big", 100, 100.0, 8)

    # Ask for 5 globally: per-key admits, global (2) is short -> :global_empty.
    assert {:error, :global_empty, _} = SharedPoolBucket.acquire(sp, "big2", 100, 100.0, 5)

    # Nothing drained: the global pool is still at 2 (no time advanced).
    assert {:ok, 2} = SharedPoolBucket.global_level(sp)
  end

  test "name option registers the process under the given name" do
    {:ok, _pid} =
      SharedPoolBucket.start_link(
        name: :spb_named,
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: &Clock.now/0,
        cleanup_interval_ms: :infinity
      )

    assert {:ok, 4, 9} = SharedPoolBucket.acquire(:spb_named, "alice", 5, 0.5)
    assert {:ok, 9} = SharedPoolBucket.global_level(:spb_named)
  end

  # -------------------------------------------------------
  # The periodic cleanup is driven by an automatically scheduled timer
  # -------------------------------------------------------

  test "the periodic cleanup timer fires and re-arms automatically" do
    test_pid = self()

    # Every cleanup pass reads the clock. This probe records each such call;
    # no other API call is issued after startup, so each tick is an automatic
    # sweep.
    clock = fn ->
      send(test_pid, :cleanup_clock_tick)
      0
    end

    {:ok, _pid} =
      SharedPoolBucket.start_link(
        global_capacity: 10,
        global_refill_rate: 1.0,
        clock: clock,
        cleanup_interval_ms: 25
      )

    # The first tick proves the startup timer fired; the second proves the pass
    # re-armed the next one, so the sweep repeats rather than running just once.
    # A scheduler that never arms Process.send_after would produce no ticks.
    assert_receive :cleanup_clock_tick, 1_000
    assert_receive :cleanup_clock_tick, 1_000
  end
end
