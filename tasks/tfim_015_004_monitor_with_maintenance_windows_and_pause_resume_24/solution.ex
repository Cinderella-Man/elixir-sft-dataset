  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)

    assert :ok = ManagedMonitor.deregister(mon, "web")
    assert {:error, :not_found} = ManagedMonitor.status(mon, "web")
    assert ManagedMonitor.statuses(mon) == %{}
  end