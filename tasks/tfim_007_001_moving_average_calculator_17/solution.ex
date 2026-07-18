  test "different EMA periods on the same stream produce different results", %{ma: ma} do
    Enum.each(
      [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 9.0, 10.0],
      &MovingAverage.push(ma, "multi", &1)
    )

    assert {:ok, ema3} = MovingAverage.get(ma, "multi", :ema, 3)
    assert {:ok, ema10} = MovingAverage.get(ma, "multi", :ema, 10)

    # EMA with smaller period reacts faster — should be closer to 10
    assert ema3 > ema10
  end