  test "failure rate at exactly threshold triggers :down", %{mon: mon} do
    check = CheckFn.build("svc")
    # window_size=5, threshold=0.6 → need 3/5 errors = 0.6
    RateMonitor.register(mon, "svc", check, 1_000, window_size: 5, threshold: 0.6)

    # 2 ok then 3 errors → 3/5 = 0.6
    results = [:ok, :ok, {:error, :a}, {:error, :b}, {:error, :c}]

    for result <- results do
      CheckFn.set_result("svc", result)
      Clock.advance(1_000)
      trigger_check(mon, "svc")
    end

    assert {:ok, %{status: :down, failure_rate: rate}} = RateMonitor.status(mon, "svc")
    assert_in_delta rate, 0.6, 0.01
    assert Notifications.count() == 1
  end