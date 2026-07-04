  test "per-key refill caps at per-key capacity", %{sp: sp} do
    # Drain alice (cap 2)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)
    SharedPoolBucket.acquire(sp, "alice", 2, 1.0)

    # Idle a very long time — alice must cap at 2, not overflow
    Clock.advance(1_000_000)

    assert {:ok, 2} = SharedPoolBucket.key_level(sp, "alice", 2, 1.0)
  end