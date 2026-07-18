  test "different stream names are completely independent", %{ma: ma} do
    Enum.each([100.0, 200.0, 300.0], &MovingAverage.push(ma, "a", &1))
    MovingAverage.push(ma, "b", 999.0)

    assert {:ok, sma_a} = MovingAverage.get(ma, "a", :sma, 3)
    assert_close(sma_a, 200.0)

    assert {:ok, sma_b} = MovingAverage.get(ma, "b", :sma, 3)
    assert_close(sma_b, 999.0)

    assert {:error, :no_data} = MovingAverage.get(ma, "c", :sma, 3)
  end