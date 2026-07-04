  test "get returns nil for a histogram that has never been observed" do
    assert Metrics.get(:never) == nil
  end