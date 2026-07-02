  test "state after register has correct name, sku, quantity, and status", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    state = InventoryAggregate.state(agg, "prod:1")
    assert state.name == "Widget"
    assert state.sku == "WDG-001"
    assert state.quantity_on_hand == 0
    assert state.status == :registered
  end