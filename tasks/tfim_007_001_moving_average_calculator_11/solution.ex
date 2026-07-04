  test "EMA cold-start: fewer values than the period still computes", %{ma: ma} do
    # Sequence: [4, 8], period 10, k = 2/11 ≈ 0.18182
    # Step 0: ema = 4
    # Step 1: ema = 8 * (2/11) + 4 * (9/11) = 16/11 + 36/11 = 52/11 ≈ 4.7273
    MovingAverage.push(ma, "e", 4.0)
    MovingAverage.push(ma, "e", 8.0)

    assert {:ok, result} = MovingAverage.get(ma, "e", :ema, 10)
    assert_close(result, 52.0 / 11.0)
  end