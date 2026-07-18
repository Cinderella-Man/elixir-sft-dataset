  test "events carry relevant data", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 200})
    InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 75})

    [registered, received, shipped] = InventoryAggregate.events(agg, "prod:1")

    assert registered.type == :product_registered
    assert Map.has_key?(registered, :name) or Map.has_key?(registered, :product_name)
    assert Map.has_key?(registered, :sku)

    assert received.type == :stock_received
    assert received.quantity == 200

    assert shipped.type == :stock_shipped
    assert shipped.quantity == 75
  end