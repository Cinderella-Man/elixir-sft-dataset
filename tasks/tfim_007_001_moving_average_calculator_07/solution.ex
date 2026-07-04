  test "SMA with different periods on the same stream", %{ma: ma} do
    Enum.each([2.0, 4.0, 6.0, 8.0, 10.0], &MovingAverage.push(ma, "s", &1))

    assert {:ok, sma2} = MovingAverage.get(ma, "s", :sma, 2)
    # Last 2: [8, 10] -> 9.0
    assert_close(sma2, 9.0)

    assert {:ok, sma5} = MovingAverage.get(ma, "s", :sma, 5)
    # All 5: [2, 4, 6, 8, 10] -> 6.0
    assert_close(sma5, 6.0)
  end