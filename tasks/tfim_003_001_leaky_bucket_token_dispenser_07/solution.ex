  test "tokens refill based on elapsed time", %{lb: lb} do
    # Capacity 10, refill rate 5 tokens/sec. Drain all 10.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 5)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 10, 5)

    # Advance 1 second => 5 tokens refilled
    Clock.advance(1_000)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 10, 5)
  end