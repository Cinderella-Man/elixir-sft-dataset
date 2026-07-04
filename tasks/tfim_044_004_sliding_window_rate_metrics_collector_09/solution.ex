  test "reset deletes all buckets for a name", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits, 3)
    set_time(clock, 10)
    Metrics.increment(:hits, 2)

    Metrics.reset(:hits)
    assert Metrics.count(:hits) == 0
    assert Metrics.rate(:hits, 1000) == 0
  end