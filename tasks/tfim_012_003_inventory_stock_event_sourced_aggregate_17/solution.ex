  test "adjust on unregistered product fails", %{agg: agg} do
    assert {:error, :not_registered} = InventoryAggregate.execute(agg, "prod:1", {:adjust, 5})
  end