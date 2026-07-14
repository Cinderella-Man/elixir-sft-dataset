  test "WMA values buffer is bounded by max_period", %{wma: s} do
    for v <- 1..20, do: WeightedMovingAverage.push(s, "a", v)

    # Ask for period 3 — max_period becomes 3, buffer trims to 3.
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    # Push more values; buffer should stay at 3 (the current max_period).
    for v <- 21..30, do: WeightedMovingAverage.push(s, "a", v)
    _ = WeightedMovingAverage.get(s, "a", :wma, 3)

    # Only the newest three values ([30, 29, 28]) are retained, so a wider
    # window cold-starts over exactly those three rather than reaching back
    # into the discarded history.
    # WMA = (3*30 + 2*29 + 1*28) / 6 = (90 + 58 + 28) / 6 = 176 / 6
    {:ok, wide} = WeightedMovingAverage.get(s, "a", :wma, 10)
    assert close_to(wide, 176 / 6)

    # Three retained values cannot satisfy an HMA that needs four.
    assert {:error, :insufficient_data} = WeightedMovingAverage.get(s, "a", :hma, 4)
  end