  test "can acquire multiple tokens at once", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 5, 1, 3)
    assert {:ok, 0} = LeakyBucket.acquire(lb, "b", 5, 1, 2)
  end