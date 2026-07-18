  test "prune deletes a bucket sitting exactly on the retention cutoff", %{clock: clock} do
    set_time(clock, 40)
    Metrics.increment(:edge, 7)

    set_time(clock, 41)
    Metrics.increment(:edge, 3)

    set_time(clock, 100)
    # cutoff = 100 - 60 = 40 => bucket 40 is deleted, bucket 41 survives
    assert Metrics.prune(60) == 1
    assert Metrics.count(:edge) == 3
    assert Metrics.rate(:edge, 1000) == 3
  end