  test "stale schedule message after deregister has no effect", %{mon: mon} do
    CheckFn.set_result("web", {:error, :boom})
    check = CheckFn.build("web")
    AsyncMonitor.register(mon, "web", check, 1_000)
    AsyncMonitor.deregister(mon, "web")

    send(mon, {:schedule_check, "web"})
    _ = AsyncMonitor.statuses(mon)
    Process.sleep(10)
    _ = AsyncMonitor.statuses(mon)

    assert {:error, :not_found} = AsyncMonitor.status(mon, "web")
    assert Notifications.count() == 0
  end