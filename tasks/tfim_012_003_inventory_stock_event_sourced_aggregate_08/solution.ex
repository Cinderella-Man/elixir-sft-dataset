  test "receive_stock of zero or negative quantity fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 0})

    assert {:error, :invalid_quantity} =
             InventoryAggregate.execute(agg, "prod:1", {:receive_stock, -10})
  end