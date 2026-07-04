  test "reset leaves other names intact", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a)
    Metrics.increment(:b)
    Metrics.reset(:a)
    assert Metrics.count(:a) == 0
    assert Metrics.count(:b) == 1
  end