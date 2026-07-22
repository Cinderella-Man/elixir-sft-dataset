  test "a lease expires exactly AT its deadline, not one tick later", %{lb: lb} do
    {:ok, _lease, _} = LeaseBucket.acquire_lease(lb, "edge", 5, 1.0, 2, 1_000)

    # One millisecond before the deadline the lease is still outstanding...
    Clock.advance(999)
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "edge")

    # ...and at expires_at == now (the documented <= rule) it is gone.
    Clock.advance(1)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "edge")
  end