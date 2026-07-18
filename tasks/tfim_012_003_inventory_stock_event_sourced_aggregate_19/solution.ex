  test "failed commands produce no events", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 999})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, -5})

    events = InventoryAggregate.events(agg, "prod:1")
    assert length(events) == 1
    assert hd(events).type == :product_registered
  end