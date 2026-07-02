  test "global pool drains across different keys", %{sp: sp} do
    # Alice takes 3, Bob takes 3 — each has their own per-key budget,
    # but the global pool should be at 10 - 3 - 3 = 4
    SharedPoolBucket.acquire(sp, "alice", 5, 1.0, 3)
    SharedPoolBucket.acquire(sp, "bob", 5, 1.0, 3)

    assert {:ok, 4} = SharedPoolBucket.global_level(sp)
  end