  test "expired leases are cleaned up by sweep", %{mgr: mgr} do
    for i <- 1..100 do
      {:ok, _} = LeaseManager.acquire(mgr, "resource_#{i}", :owner)
    end

    Clock.advance(1_100)

    send(mgr, :cleanup)
    LeaseManager.holder(mgr, :barrier)

    # Every swept resource is free again, and can be leased by a new owner.
    for i <- 1..100 do
      assert {:error, :available} = LeaseManager.holder(mgr, "resource_#{i}")
      assert {:ok, _} = LeaseManager.acquire(mgr, "resource_#{i}", :next_owner)
    end
  end