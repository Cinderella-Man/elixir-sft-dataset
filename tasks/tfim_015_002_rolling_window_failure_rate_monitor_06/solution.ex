  test "service does NOT go :down before window is full", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    # window_size=5, threshold=0.6
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 4 failures — window not full yet (need 5 checks)
    for _i <- 1..4 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, info} = RateMonitor.status(mon, "db")
    refute info.status == :down, "should not be :down before window is full"
    assert info.checks_in_window == 4
  end