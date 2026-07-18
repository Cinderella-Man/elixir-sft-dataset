  test "increment with an amount of 0 creates a missing counter at 0" do
    assert Metrics.get(:fresh_zero) == nil
    assert :ok = Metrics.increment(:fresh_zero, 0)
    assert Metrics.get(:fresh_zero) == 0
    assert Metrics.all()[:fresh_zero] == 0
  end