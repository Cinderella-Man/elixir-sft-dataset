  test "HMA(period=4) with just-enough history computes correctly", %{wma: s} do
    values = [1, 2, 3, 4]
    for v <- values, do: WeightedMovingAverage.push(s, "a", v)

    # wma1_period = 2, wma2_period = 4, buffer_size = round(sqrt(4)) = 2
    # Replay oldest-first = [1, 2, 3, 4]:
    #   step 1 (only 1 seen, newest-first [1]):
    #     WMA cold-start uses weights n..1 over n values, where n is
    #     min(requested period, available window) — not the full requested period.
    #     For 1 value with period 2: weights [1], denominator 1 → WMA = 1.0.
    #     wma1 over period 2 using [1]: 1.0
    #     wma2 over period 4 with [1]: weights [1], denominator 1 → 1.0
    #   raw_1 = 2*1 - 1 = 1.0
    # step 2 (newest-first [2, 1]):
    #   wma1 over period 2 with [2, 1]: (2*2 + 1*1)/3 = 5/3
    #   wma2 over period 4 with [2, 1]: weights [2, 1], denominator 3 → (2*2+1*1)/3 = 5/3
    #   raw_2 = 2*(5/3) - 5/3 = 5/3
    # step 3 (newest-first [3, 2, 1]):
    #   wma1 over period 2 with [3, 2, 1] → take first 2 → [3, 2]: (2*3+1*2)/3 = 8/3
    #   wma2 over period 4 with [3, 2, 1]: weights [3,2,1] → (9+4+1)/6 = 14/6 = 7/3
    #   raw_3 = 2*(8/3) - 7/3 = 16/3 - 7/3 = 9/3 = 3.0
    # step 4 (newest-first [4, 3, 2, 1]):
    #   wma1 over period 2 with [4, 3]: (2*4+1*3)/3 = 11/3
    #   wma2 over period 4 with [4, 3, 2, 1]: (4*4+3*3+2*2+1*1)/10 = (16+9+4+1)/10 = 30/10 = 3.0
    #   raw_4 = 2*(11/3) - 3 = 22/3 - 9/3 = 13/3
    #
    # raw_buffer (newest-first, trimmed to 2): [13/3, 3.0]
    # HMA = WMA([13/3, 3.0], period 2) = (2*13/3 + 3.0)/3 = (35/3)/3 = 35/9

    expected = 35 / 9
    {:ok, result} = WeightedMovingAverage.get(s, "a", :hma, 4)
    assert close_to(result, expected, 1.0e-9)
  end