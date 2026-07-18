  test "ship_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 0})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, -5})
  end