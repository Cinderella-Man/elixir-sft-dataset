  test "negative adjustment decreases quantity", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, -20})
    assert event.quantity == -20

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 30
  end