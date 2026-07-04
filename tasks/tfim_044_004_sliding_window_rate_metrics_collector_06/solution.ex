  test "rate excludes events older than the window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)
    Metrics.increment(:hits)

    set_time(clock, 30)
    Metrics.increment(:hits)

    # now = 100, window 60 => second > 40 => none of {0,0,30}
    set_time(clock, 100)
    assert Metrics.rate(:hits, 60) == 0

    # now = 100, window 90 => second > 10 => only the event at 30
    assert Metrics.rate(:hits, 90) == 1
  end