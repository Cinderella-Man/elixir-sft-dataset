  test "old results are evicted from the window", %{mon: mon} do
    check = CheckFn.build("svc")
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 3, threshold: 0.6)

    # 3 errors → [err, err, err] → :down
    CheckFn.set_result("svc", {:error, :x})

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down}} = RateMonitor.status(mon, "svc")

    # 3 successes → [ok, ok, ok] — old errors are fully evicted
    CheckFn.set_result("svc", :ok)

    for _ <- 1..3 do
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :up, failure_rate: +0.0, checks_in_window: 3}} =
             RateMonitor.status(mon, "svc")
  end