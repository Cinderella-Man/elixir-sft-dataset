  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")
    assert :ok = AsyncMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = AsyncMonitor.status(mon, "web")
  end