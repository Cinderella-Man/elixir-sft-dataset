  test "ship_stock decreases quantity_on_hand", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 40})
    assert event.type == :stock_shipped

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 60
  end