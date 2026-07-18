  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert TaskAggregate.state(agg, "nonexistent") == nil
  end