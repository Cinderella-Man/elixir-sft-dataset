  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)
    Monitor.deregister(mon, "web")
    assert :ok = Monitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending}} = Monitor.status(mon, "web")
  end