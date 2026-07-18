  test "requesting more tokens than capacity always fails", %{lb: lb} do
    assert {:error, :empty, _} = LeakyBucket.acquire(lb, "b", 5, 1, 6)
  end