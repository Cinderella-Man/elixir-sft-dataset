  test "capacity of 1 allows exactly one acquire", %{lb: lb} do
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 1, 1)
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 1, 1)
  end