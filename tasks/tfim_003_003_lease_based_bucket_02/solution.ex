  test "acquire_lease reserves tokens and returns a lease id", %{lb: lb} do
    assert {:ok, lease_id, 7} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)
    assert is_reference(lease_id)

    assert {:ok, 1} = LeaseBucket.active_leases(lb, "k")
  end