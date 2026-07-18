  test "multiple outstanding leases are tracked independently", %{lb: lb} do
    {:ok, l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 4, 60_000)
    {:ok, l3, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 2, 60_000)

    assert {:ok, 3} = LeaseBucket.active_leases(lb, "k")

    # Cancelling l2 refunds 4 tokens
    assert :ok = LeaseBucket.release(lb, "k", l2, :cancelled)
    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # 4 tokens refunded + 1 still free = 5 free
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 5, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", l1, :completed)
    assert :ok = LeaseBucket.release(lb, "k", l3, :cancelled)
  end