  test "count is nil-safe by returning 0 for unknown names" do
    assert Metrics.count(:unknown) == 0
  end