  test "retry_after_ms estimates the milliseconds until the deficit refills", %{lb: lb} do
    # Capacity 5, reserve 3 → 2 tokens free.
    assert {:ok, _, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    # A second 3-token request has a 1-token deficit; at 1.0 token/sec that
    # is 1000 ms until enough tokens refill.
    assert {:error, :empty, 1000} =
             LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
  end