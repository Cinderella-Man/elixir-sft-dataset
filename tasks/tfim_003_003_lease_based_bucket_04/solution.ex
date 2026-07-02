  test "release :cancelled refunds the tokens", %{lb: lb} do
    assert {:ok, lease_id, 2} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 3, 60_000)

    assert :ok = LeaseBucket.release(lb, "k", lease_id, :cancelled)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")

    # Full balance restored — can take another 5-token lease
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "k", 5, 1.0, 5, 60_000)
  end