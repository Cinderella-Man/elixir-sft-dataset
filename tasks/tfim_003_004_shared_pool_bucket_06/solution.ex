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