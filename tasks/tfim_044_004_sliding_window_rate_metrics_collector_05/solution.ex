  test "rate counts events within the window", %{clock: clock} do
    set_time(clock, 0)
    Metrics.increment(:hits)
    Metrics.increment(:hits)

    set_time(clock, 30)
    Metrics.increment(:hits)

    # now = 30, window 60 => second > -30 => all three
    assert Metrics.rate(:hits, 60) == 3
  end