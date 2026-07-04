  test "notification includes the failure rate", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 3, threshold: 0.6)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    [{name, rate}] = Notifications.all()
    assert name == "db"
    assert rate == 1.0
  end