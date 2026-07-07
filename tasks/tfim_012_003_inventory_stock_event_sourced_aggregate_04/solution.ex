  test "registering an already-registered product fails", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:error, :already_registered} =
             InventoryAggregate.execute(agg, "prod:1", {:register, "Other", "OTH-001"})
  end