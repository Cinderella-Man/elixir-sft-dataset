  test "notification fires again on a second down after recovery", %{mon: mon} do
    CheckFn.set_result("api", {:error, :crash})
    check = CheckFn.build("api")
    AsyncMonitor.register(mon, "api", check, 1_000)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 1

    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")

    CheckFn.set_result("api", {:error, :oom})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert Notifications.count() == 2
    assert Notifications.all() == [{"api", :crash}, {"api", :oom}]
  end