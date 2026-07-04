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