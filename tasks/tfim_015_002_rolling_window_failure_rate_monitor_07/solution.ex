  test "service goes :down when failure rate >= threshold with full window", %{mon: mon} do
    CheckFn.set_result("db", {:error, :timeout})
    check = CheckFn.build("db")
    RateMonitor.register(mon, "db", check, 1_000, window_size: 5, threshold: 0.6)

    # 5 failures → rate = 1.0 >= 0.6
    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "db")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "db")
    assert rate == 1.0
  end