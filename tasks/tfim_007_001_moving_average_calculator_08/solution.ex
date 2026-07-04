  test "EMA with a single value equals that value", %{ma: ma} do
    MovingAverage.push(ma, "e", 42.0)
    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 42.0)
  end