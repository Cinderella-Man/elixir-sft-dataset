  test "SMA only retains up to max_period values, not the full stream", %{ma: ma} do
    # First, request SMA with period 5 to establish max_period
    MovingAverage.push(ma, "mem", 0.0)
    MovingAverage.get(ma, "mem", :sma, 5)

    # Push 1000 more values
    for i <- 1..1000, do: MovingAverage.push(ma, "mem", i * 1.0)

    # SMA should still be correct (last 5: [996, 997, 998, 999, 1000])
    assert {:ok, result} = MovingAverage.get(ma, "mem", :sma, 5)
    assert_close(result, 998.0)

    # Because storage is bounded by max_period, the older values are gone for
    # good: a much wider window can only average the handful of retained
    # values. An unbounded buffer would answer 900.5 here (the true mean of
    # 801..1000), while a buffer holding at most ~10 recent values cannot
    # produce anything below 995.5 (the mean of 991..1000).
    assert {:ok, wide} = MovingAverage.get(ma, "mem", :sma, 200)

    assert wide > 995.0,
           "Expected a bounded buffer, but SMA over period 200 answered #{wide}, " <>
             "which implies far more than max_period values are still stored"
  end