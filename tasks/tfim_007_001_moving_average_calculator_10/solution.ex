  test "EMA with period 1 always equals the latest value", %{ma: ma} do
    # k = 2/(1+1) = 1.0, so ema = value * 1 + prev * 0 = value
    Enum.each([5.0, 15.0, 25.0, 100.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 1)
    assert_close(result, 100.0)
  end