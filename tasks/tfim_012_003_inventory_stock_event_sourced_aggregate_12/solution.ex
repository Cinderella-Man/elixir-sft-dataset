  test "ship_stock on unregistered product fails", %{agg: agg} do
    assert {:error, :not_registered} =
             InventoryAggregate.execute(agg, "prod:1", {:ship_stock, 10})
  end