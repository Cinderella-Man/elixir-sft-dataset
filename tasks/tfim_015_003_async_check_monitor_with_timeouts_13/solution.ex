  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)

    assert :ok = AsyncMonitor.deregister(mon, "web")
    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert AsyncMonitor.statuses(mon) == %{}
  end