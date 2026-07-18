  test "checks_in_window never exceeds window_size", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3)

    CheckFn.set_result("svc", :ok)

    for _ <- 1..10 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{checks_in_window: 3}} = RateMonitor.status(mon, "svc")
  end