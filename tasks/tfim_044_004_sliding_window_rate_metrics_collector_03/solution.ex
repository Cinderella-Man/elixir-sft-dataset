  test "increment supports an explicit amount", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits, 5)
    Metrics.increment(:hits, 3)
    assert Metrics.count(:hits) == 8
  end