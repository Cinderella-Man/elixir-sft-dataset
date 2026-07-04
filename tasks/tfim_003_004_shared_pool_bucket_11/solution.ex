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