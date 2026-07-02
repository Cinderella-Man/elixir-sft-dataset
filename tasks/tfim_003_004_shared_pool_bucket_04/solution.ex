  test "per-key exhaustion returns :key_empty", %{sp: sp} do
    # Alice drains her per-key (capacity 3, small relative to global 10)
    for _ <- 1..3, do: SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert {:error, :key_empty, retry_after} =
             SharedPoolBucket.acquire(sp, "alice", 3, 1.0)

    assert is_integer(retry_after)
    assert retry_after > 0

    # Bob is unaffected — global pool still has 7
    assert {:ok, 2, 6} = SharedPoolBucket.acquire(sp, "bob", 3, 1.0)
  end