  test "global refill caps at global capacity", %{sp: sp} do
    # Drain global partially
    for _ <- 1..5, do: SharedPoolBucket.acquire(sp, "alice", 10, 10.0)

    # Idle a very long time — global caps at 10
    Clock.advance(1_000_000)

    assert {:ok, 10} = SharedPoolBucket.global_level(sp)
  end