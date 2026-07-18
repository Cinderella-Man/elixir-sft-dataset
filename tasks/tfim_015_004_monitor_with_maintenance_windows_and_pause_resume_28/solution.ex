  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    ManagedMonitor.register(mon, "web", check, 1_000)
    ManagedMonitor.deregister(mon, "web")
    assert :ok = ManagedMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = ManagedMonitor.status(mon, "web")
  end