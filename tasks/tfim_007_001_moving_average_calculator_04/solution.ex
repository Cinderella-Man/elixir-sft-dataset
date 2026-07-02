  test "SMA cold-start: fewer values than the period", %{ma: ma} do
    # Push 3 values, request SMA over period 5
    MovingAverage.push(ma, "s", 2.0)
    MovingAverage.push(ma, "s", 4.0)
    MovingAverage.push(ma, "s", 6.0)

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [2, 4, 6] = 4.0
    assert_close(result, 4.0)
  end