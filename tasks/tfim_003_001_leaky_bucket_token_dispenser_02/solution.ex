  test "new bucket starts full at capacity", %{lb: lb} do
    assert {:ok, 4} = LeakyBucket.acquire(lb, "b", 5, 1)
  end