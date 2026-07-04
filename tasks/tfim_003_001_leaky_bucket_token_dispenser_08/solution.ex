  test "partial refill works correctly", %{lb: lb} do
    # Capacity 10, refill rate 10 tokens/sec. Drain all.
    for _ <- 1..10, do: LeakyBucket.acquire(lb, "b", 10, 10)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 10, 10)

    # Advance 500ms => 5 tokens refilled
    Clock.advance(500)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 10, 10)
  end