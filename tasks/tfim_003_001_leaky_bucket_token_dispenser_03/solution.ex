  test "drains tokens one at a time", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 1} = LeakyBucket.acquire(lb, "b", 3, 1)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 3, 1)
  end