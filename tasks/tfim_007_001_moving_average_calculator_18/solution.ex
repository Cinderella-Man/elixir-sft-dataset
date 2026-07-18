  test "interleaved pushes and gets produce correct results", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, r1} = MovingAverage.get(ma, "s", :sma, 3)
    assert_close(r1, 10.0)

    MovingAverage.push(ma, "s", 20.0)
    assert {:ok, r2} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20]
    assert_close(r2, 15.0)

    MovingAverage.push(ma, "s", 30.0)
    assert {:ok, r3} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [10, 20, 30]
    assert_close(r3, 20.0)

    MovingAverage.push(ma, "s", 40.0)
    assert {:ok, r4} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [20, 30, 40] — 10 dropped
    assert_close(r4, 30.0)

    MovingAverage.push(ma, "s", 50.0)
    assert {:ok, r5} = MovingAverage.get(ma, "s", :sma, 3)
    # mean of [30, 40, 50]
    assert_close(r5, 40.0)
  end