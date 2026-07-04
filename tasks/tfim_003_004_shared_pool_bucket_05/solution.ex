  test "rejected acquire does not drain either level", %{sp: sp} do
    # Exhaust Alice
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)

    # Reject
    assert {:error, :key_empty, _} = SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    # Global pool must still be at 7 — the rejected acquire must not have drained
    assert {:ok, 7} = SharedPoolBucket.global_level(sp)
  end