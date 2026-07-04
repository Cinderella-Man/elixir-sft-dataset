  test "multiple receives accumulate", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 75})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 125
  end