  test "a :down service recovers when failure rate drops below threshold", %{mon: mon} do
    check = CheckFn.build("api")
    RateMonitor.register(mon, "api", check, 1_000, window_size: 5, threshold: 0.6)

    # Fill window with all errors → :down
    CheckFn.set_result("api", {:error, :crash})

    for _ <- 1..5 do
      Clock.advance(1_000)
      trigger_check(mon, "api")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # Now successes push errors out of the window
    # After 1 ok: [err, err, err, err, ok] → 4/5 = 0.8 ≥ 0.6 → still :down
    CheckFn.set_result("api", :ok)
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # After 2 ok: [err, err, err, ok, ok] → 3/5 = 0.6 → still :down
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "api")

    # After 3 ok: [err, err, ok, ok, ok] → 2/5 = 0.4 < 0.6 → :up!
    Clock.advance(1_000)
    trigger_check(mon, "api")
    assert {:ok, %{status: :up, failure_rate: rate}} = RateMonitor.status(mon, "api")
    assert_in_delta rate, 0.4, 0.01
  end