  test "requesting a larger period grows the buffer to accommodate it", %{ma: ma} do
    # Start with period 3
    Enum.each(1..20 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma3} = MovingAverage.get(ma, "grow", :sma, 3)
    # mean of [18, 19, 20]
    assert_close(sma3, 19.0)

    # Now request period 10 — the buffer should still work,
    # though values before the previous max_period may be lost.
    # Push 10 more values so we have enough for period 10.
    Enum.each(21..30 |> Enum.map(&(&1 * 1.0)), &MovingAverage.push(ma, "grow", &1))
    assert {:ok, sma10} = MovingAverage.get(ma, "grow", :sma, 10)
    # Last 10: [21..30], mean = 25.5
    assert_close(sma10, 25.5)
  end