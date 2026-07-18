  test "constant values yield that constant for both SMA and EMA", %{ma: ma} do
    for _ <- 1..20, do: MovingAverage.push(ma, "flat", 7.0)

    assert {:ok, sma} = MovingAverage.get(ma, "flat", :sma, 5)
    assert_close(sma, 7.0)

    assert {:ok, ema} = MovingAverage.get(ma, "flat", :ema, 5)
    assert_close(ema, 7.0)
  end