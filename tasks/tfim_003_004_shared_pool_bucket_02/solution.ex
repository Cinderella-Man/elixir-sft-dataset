  test "both levels drain on a successful acquire", %{sp: sp} do
    # Per-key: 5 capacity, 0.5/sec. Global: 10 capacity, 1/sec.
    assert {:ok, 4, 9} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
    assert {:ok, 3, 8} = SharedPoolBucket.acquire(sp, "alice", 5, 0.5)
  end