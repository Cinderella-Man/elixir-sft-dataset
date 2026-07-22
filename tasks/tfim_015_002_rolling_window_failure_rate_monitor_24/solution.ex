  test "a failing check keeps a :pending service :pending before the window fills",
       %{mon: mon} do
    CheckFn.set_result("db2", {:error, :timeout})
    RateMonitor.register(mon, "db2", CheckFn.build("db2"), 1_000, window_size: 5, threshold: 0.6)

    # One failed check in a partial window: it cannot be :down, and because the
    # single outcome is an error the service must stay :pending (not flip :up).
    Clock.advance(1_000)
    trigger_check(mon, "db2")

    assert {:ok, info} = RateMonitor.status(mon, "db2")
    assert info.status == :pending
    assert info.checks_in_window == 1
  end