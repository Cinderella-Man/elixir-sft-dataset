  test "cleanup keeps buckets with active leases", %{lb: lb} do
    # Long-running lease keeps the bucket alive
    {:ok, l, _} = LeaseBucket.acquire_lease(lb, "alive", 5, 1.0, 2, 3_600_000)

    # Short lease expires
    LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 1, 100)
    Clock.advance(10_000)

    send(lb, :cleanup)

    # A synchronous call is served only after the cleanup message is handled.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "sentinel")

    # The long lease survived the sweep: it is still counted and still
    # releasable by its id.
    assert {:ok, 1} = LeaseBucket.active_leases(lb, "alive")
    assert :ok = LeaseBucket.release(lb, "alive", l, :completed)
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "alive")

    # The bucket whose only lease expired is back to fresh behavior.
    assert {:ok, 0} = LeaseBucket.active_leases(lb, "gone")
    assert {:ok, _, 0} = LeaseBucket.acquire_lease(lb, "gone", 2, 10.0, 2, 100)
  end