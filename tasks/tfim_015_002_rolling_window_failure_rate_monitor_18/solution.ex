  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    RateMonitor.register(mon, "web", check, 1_000)
    RateMonitor.deregister(mon, "web")

    send(mon, {:check, "web"})
    _ = RateMonitor.statuses(mon)

    assert {:error, :not_found} = RateMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end