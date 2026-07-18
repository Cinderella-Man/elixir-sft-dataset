  test "stale maintenance_end after deregister has no effect", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)
    ManagedMonitor.maintenance(mon, "web", 5_000)
    ManagedMonitor.deregister(mon, "web")

    send(mon, {:maintenance_end, "web"})
    _ = ManagedMonitor.statuses(mon)

    assert {:error, :not_found} = ManagedMonitor.status(mon, "web")
  end