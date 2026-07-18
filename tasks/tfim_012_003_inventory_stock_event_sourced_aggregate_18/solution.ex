  test "events returns full ordered history", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 30})

    events = InventoryAggregate.events(agg, "prod:1")
    assert length(events) == 3

    assert Enum.map(events, & &1.type) == [
             :product_registered,
             :stock_received,
             :stock_shipped
           ]
  end