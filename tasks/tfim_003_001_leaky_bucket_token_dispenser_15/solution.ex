  test "interleaved operations on multiple buckets", %{lb: lb} do
    assert {:ok, 1} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 4} = LeakyBucket.acquire(lb, "y", 5, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 3} = LeakyBucket.acquire(lb, "y", 5, 1)

    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "x", 2, 1)
    assert {:ok, 2} = LeakyBucket.acquire(lb, "y", 5, 1)
  end