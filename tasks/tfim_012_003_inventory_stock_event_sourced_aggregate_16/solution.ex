  test "zero adjustment fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:error, :invalid_quantity} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 0})
  end