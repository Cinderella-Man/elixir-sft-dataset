  test "deregistering a service removes it from statuses", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)

    assert :ok = RateMonitor.deregister(mon, "web")
    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert RateMonitor.statuses(mon) == %{}
  end