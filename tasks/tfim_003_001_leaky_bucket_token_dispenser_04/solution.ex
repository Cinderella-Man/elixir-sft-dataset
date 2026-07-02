  test "rejects when bucket is empty", %{lb: lb} do
    for _ <- 1..3, do: LeakyBucket.acquire(lb, "b", 3, 1)

    assert {:error, :empty, retry_after} =
             LeakyBucket.acquire(lb, "b", 3, 1)

    assert is_integer(retry_after)
    assert retry_after > 0
  end