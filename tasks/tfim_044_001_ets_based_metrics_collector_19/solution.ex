  test "snapshot/0 returns the same data as all/0" do
    Metrics.increment(:x, 7)
    Metrics.gauge(:y, 3)
    assert Metrics.snapshot() == Metrics.all()
  end