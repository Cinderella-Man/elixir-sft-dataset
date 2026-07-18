  test "rate excludes a bucket sitting exactly on the window cutoff", %{clock: clock} do
    set_time(clock, 40)
    Metrics.increment(:edge, 7)

    set_time(clock, 41)
    Metrics.increment(:edge, 3)

    set_time(clock, 100)
    # cutoff = 100 - 60 = 40 => bucket 40 is excluded, bucket 41 is included
    assert Metrics.rate(:edge, 60) == 3
  end