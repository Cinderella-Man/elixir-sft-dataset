  test "events for unknown aggregate returns empty list", %{agg: agg} do
    assert InventoryAggregate.events(agg, "nonexistent") == []
  end