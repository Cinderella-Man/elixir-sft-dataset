  test "returns error when no data has been pushed", %{ma: ma} do
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :sma, 5)
    assert {:error, :no_data} = MovingAverage.get(ma, "empty", :ema, 5)
  end