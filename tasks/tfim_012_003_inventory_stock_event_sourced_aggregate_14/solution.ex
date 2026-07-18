  test "positive adjustment increases quantity", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 10})
    assert event.type == :stock_adjusted
    assert event.quantity == 10

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 60
  end