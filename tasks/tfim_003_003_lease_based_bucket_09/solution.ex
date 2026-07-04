  test "acquire/release trigger bucket-level expiry of OTHER leases", %{lb: lb} do
    # Short-timeout lease
    {:ok, _l1, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 500)

    # Long-timeout lease
    {:ok, l2, _} = LeaseBucket.acquire_lease(lb, "k", 10, 1.0, 3, 60_000)

    assert {:ok, 2} = LeaseBucket.active_leases(lb, "k")

    # Advance past the short lease's expiry but within the long lease's
    Clock.advance(1_000)

    # Any operation should expire the short lease
    assert :ok = LeaseBucket.release(lb, "k", l2, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "k")
  end