  test "events in the same second accumulate in one bucket", %{clock: clock} do
    set_time(clock, 42)
    Metrics.increment(:hits, 4)
    Metrics.increment(:hits, 6)
    assert Metrics.rate(:hits, 1) == 10
  end