  test "different bucket names are completely independent", %{lb: lb} do
    # Exhaust bucket "a"
    for _ <- 1..3, do: LeakyBucket.acquire(lb, "a", 3, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "a", 3, 1)

    # Bucket "b" should be unaffected
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 3, 1)
  end