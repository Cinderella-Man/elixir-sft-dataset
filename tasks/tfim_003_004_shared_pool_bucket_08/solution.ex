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