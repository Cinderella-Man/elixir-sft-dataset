  test "refill allows requests again after draining", %{lb: lb} do
    # Capacity 2, refill 1/sec. Drain it.
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 2, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Advance 1 second => 1 token refilled
    Clock.advance(1_000)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Empty again
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 2, 1)

    # Advance another second => 1 more token
    Clock.advance(1_000)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 2, 1)
  end