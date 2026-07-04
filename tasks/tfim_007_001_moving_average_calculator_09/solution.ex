  test "EMA hand-calculated over a known sequence", %{ma: ma} do
    # Sequence: [10, 20, 30]
    # Period: 3, k = 2/(3+1) = 0.5
    #
    # Step 0: ema = 10
    # Step 1: ema = 20 * 0.5 + 10 * 0.5 = 15
    # Step 2: ema = 30 * 0.5 + 15 * 0.5 = 22.5
    Enum.each([10.0, 20.0, 30.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 3)
    assert_close(result, 22.5)
  end