  test "works with very high refill rate", %{lb: lb} do
    # Capacity 100, refill 1000/sec. Drain all.
    for _ <- 1..100, do: LeakyBucket.acquire(lb, "b", 100, 1_000)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 100, 1_000)

    # 100ms => 100 tokens refilled (capped at capacity)
    Clock.advance(100)
    assert {:ok, 99} = LeakyBucket.acquire(lb, "b", 100, 1_000)
  end