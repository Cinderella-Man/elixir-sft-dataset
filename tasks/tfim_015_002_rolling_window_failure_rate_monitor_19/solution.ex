  test "can re-register a service after deregistering it", %{mon: mon} do
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")
    assert :ok = RateMonitor.register(mon, "web", check, 1_000)

    assert {:ok, %{status: :pending, checks_in_window: 0}} =
             RateMonitor.status(mon, "web")
  end