  test "ship exact quantity succeeds and leaves zero", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 50})
    assert {:ok, _} = InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 50})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 0
  end