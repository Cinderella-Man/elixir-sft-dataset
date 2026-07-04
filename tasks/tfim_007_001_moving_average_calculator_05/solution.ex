  test "SMA over exact period count", %{ma: ma} do
    Enum.each([10.0, 20.0, 30.0, 40.0, 50.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 5)
    # Mean of [10, 20, 30, 40, 50] = 30.0
    assert_close(result, 30.0)
  end