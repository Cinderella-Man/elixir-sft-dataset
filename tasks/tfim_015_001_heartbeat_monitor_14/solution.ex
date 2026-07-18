  test "stale check message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    Monitor.register(mon, "web", check, 1_000)
    Monitor.deregister(mon, "web")

    # Simulate a stale timer message arriving
    send(mon, {:check, "web"})
    _ = Monitor.statuses(mon)

    assert {:error, :not_found} = Monitor.status(mon, "web")
    assert Notifications.count() == 0
  end