  test "increment without labels uses the empty label set" do
    Metrics.increment(:requests)
    assert Metrics.get(:requests, %{}) == 1
  end