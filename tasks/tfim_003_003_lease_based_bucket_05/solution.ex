  test "release :completed keeps tokens consumed", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Balance is NOT refunded — only 2 tokens free
    assert {:error, :empty, _} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)
    assert {:ok, _, 1} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 1, 60_000)
  end