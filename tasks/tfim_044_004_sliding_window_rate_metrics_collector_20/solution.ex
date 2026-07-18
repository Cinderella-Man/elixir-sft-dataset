  test "prune removes stale buckets belonging to every name", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:a, 2)
    Metrics.increment(:b, 3)

    set_time(clock, 100)
    Metrics.increment(:b, 1)

    assert Metrics.prune(60) == 2
    assert Metrics.count(:a) == 0
    assert Metrics.count(:b) == 1
    assert Metrics.all() == %{b: 1}
  end