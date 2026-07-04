  test "HMA incrementally updates on new pushes", %{wma: s} do
    for v <- [1, 2, 3, 4], do: WeightedMovingAverage.push(s, "a", v)
    {:ok, h4} = WeightedMovingAverage.get(s, "a", :hma, 4)

    # Push a new value and check that HMA has been incrementally extended
    # (bootstrap path runs only once — future pushes must update the buffer).
    WeightedMovingAverage.push(s, "a", 10)
    {:ok, h5} = WeightedMovingAverage.get(s, "a", :hma, 4)

    refute close_to(h4, h5, 1.0e-12)
  end