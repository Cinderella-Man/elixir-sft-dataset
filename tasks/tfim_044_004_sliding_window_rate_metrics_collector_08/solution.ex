  test "rate is 0 for an unknown name", %{clock: clock} do
    set_time(clock, 5)
    assert Metrics.rate(:nope, 60) == 0
  end