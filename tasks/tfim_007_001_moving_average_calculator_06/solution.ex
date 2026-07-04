  test "SMA slides window: old values drop off", %{ma: ma} do
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, result} = MovingAverage.get(ma, "s", :sma, 3)
    # Last 3 values: [5, 6, 7], mean = 6.0
    assert_close(result, 6.0)
  end