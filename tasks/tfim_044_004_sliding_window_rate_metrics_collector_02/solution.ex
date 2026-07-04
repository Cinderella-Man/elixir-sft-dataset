  test "increment records events at the current second", %{clock: clock} do
    set_time(clock, 0)
    assert :ok = Metrics.increment(:hits)
    Metrics.increment(:hits)
    assert Metrics.count(:hits) == 2
  end