  test "rejects acquire when tokens exceed free balance", %{lb: lb} do
    # Capacity 5, ask for 3 first
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    # Only 2 tokens free — a 3-token ask must be rejected
    assert {:error, :empty, retry_after} =
             LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert is_integer(retry_after)
    assert retry_after > 0
  end