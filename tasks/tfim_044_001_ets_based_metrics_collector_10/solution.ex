  test "get returns nil for unknown metric" do
    assert Metrics.get(:does_not_exist) == nil
  end