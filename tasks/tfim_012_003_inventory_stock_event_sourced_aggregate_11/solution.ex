  test "ship more than available stock fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 30})

    assert {:error, :insufficient_stock} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 31})

    # Quantity unchanged after failed shipment
    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 30
  end