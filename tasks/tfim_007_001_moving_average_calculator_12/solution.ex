  test "EMA with longer known sequence", %{ma: ma} do
    # Sequence: [1, 2, 3, 4, 5], period 5, k = 2/6 = 1/3
    # Step 0: ema = 1
    # Step 1: ema = 2*(1/3) + 1*(2/3) = 4/3
    # Step 2: ema = 3*(1/3) + (4/3)*(2/3) = 1 + 8/9 = 17/9
    # Step 3: ema = 4*(1/3) + (17/9)*(2/3) = 4/3 + 34/27 = 36/27 + 34/27 = 70/27
    # Step 4: ema = 5*(1/3) + (70/27)*(2/3) = 5/3 + 140/81 = 135/81 + 140/81 = 275/81
    Enum.each([1.0, 2.0, 3.0, 4.0, 5.0], &MovingAverage.push(ma, "e", &1))

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 5)
    assert_close(result, 275.0 / 81.0)
  end