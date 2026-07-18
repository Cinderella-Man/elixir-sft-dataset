  test "prune returns the bucket count rather than the events removed", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:heavy, 5)

    set_time(clock, 1)
    Metrics.increment(:heavy, 9)

    set_time(clock, 100)
    # two buckets holding 14 events between them => 2, not 14
    assert Metrics.prune(60) == 2
    assert Metrics.count(:heavy) == 0
  end