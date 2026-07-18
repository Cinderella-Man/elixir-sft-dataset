  test "all returns per-name all-time totals", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a, 2)
    set_time(clock, 5)
    Metrics.increment(:a, 1)
    Metrics.increment(:b, 9)

    result = Metrics.all()
    assert result[:a] == 3
    assert result[:b] == 9
  end