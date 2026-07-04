  test "intermittent failures below threshold keep service :up", %{mon: mon} do
    check = CheckFn.build("flaky")
    RateMonitor.register(mon, "flaky", check, 1_000, window_size: 5, threshold: 0.6)

    # Pattern: ok, error, ok, ok, error → 2/5 = 0.4 < 0.6
    results = [:ok, {:error, :flaky}, :ok, :ok, {:error, :flaky}]

    for result <- results do
      CheckFn.set_result("flaky", result)
      Clock.advance(1_000)
      trigger_check(mon, "flaky")
    end

    assert {:ok, %{status: :up, failure_rate: rate}} = RateMonitor.status(mon, "flaky")
    assert_in_delta rate, 0.4, 0.01
    assert Notifications.count() == 0
  end