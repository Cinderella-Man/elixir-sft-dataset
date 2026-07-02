  test "SMA with a single value", %{ma: ma} do
    MovingAverage.push(ma, "s", 10.0)
    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    assert_close(result, 10.0)
  end