  test "cleanup only removes expired leases, keeps active ones", %{mgr: mgr} do
    {:ok, _} = LeaseManager.acquire(mgr, :old_resource, :alice)

    Clock.advance(900)
    {:ok, _} = LeaseManager.acquire(mgr, :new_resource, :bob)

    Clock.advance(101)

    send(mgr, :cleanup)
    LeaseManager.holder(mgr, :barrier)

    assert {:error, :available} = LeaseManager.holder(mgr, :old_resource)
    assert {:ok, :bob, _} = LeaseManager.holder(mgr, :new_resource)
  end