  test "prune deletes buckets older than the retention window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)

    set_time(clock, 50)
    Metrics.increment(:hits)

    set_time(clock, 100)
    Metrics.increment(:hits)

    # now = 100, retention 60 => delete buckets with second <= 40 => the one at 0
    assert Metrics.prune(60) == 1
    assert Metrics.count(:hits) == 2
    assert Metrics.rate(:hits, 1000) == 2
  end