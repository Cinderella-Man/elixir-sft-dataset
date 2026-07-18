  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert Aggregate.state(agg, "nonexistent") == nil
  end