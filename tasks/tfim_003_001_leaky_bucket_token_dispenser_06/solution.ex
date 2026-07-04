  test "rejects multi-token acquire when not enough tokens", %{lb: lb} do
    assert {:ok, 2} = LeakyBucket.acquire(lb, "b", 5, 1, 3)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 5, 1, 3)

    assert is_integer(retry_after)
    assert retry_after > 0
  end