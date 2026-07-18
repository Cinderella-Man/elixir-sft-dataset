  test "increment accepts an amount of zero and records no events", %{clock: clock} do
    set_time(clock, 12)
    assert :ok = Metrics.increment(:zeroed, 0)

    assert Metrics.count(:zeroed) == 0
    assert Metrics.rate(:zeroed, 1) == 0

    Metrics.increment(:zeroed, 4)
    assert Metrics.count(:zeroed) == 4
  end