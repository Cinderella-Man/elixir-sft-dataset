  test "state for unknown aggregate returns nil", %{agg: agg} do
    assert InventoryAggregate.state(agg, "nonexistent") == nil
  end