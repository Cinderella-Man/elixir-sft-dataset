  test "different aggregate ids are completely independent", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 200})

    InventoryAggregate.execute(agg, "prod:2", {:register, "Gadget", "GDG-001"})
    InventoryAggregate.execute(agg, "prod:2", {:receive_stock, 10})

    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 200
    assert InventoryAggregate.state(agg, "prod:2").quantity_on_hand == 10

    assert length(InventoryAggregate.events(agg, "prod:1")) == 2
    assert length(InventoryAggregate.events(agg, "prod:2")) == 2
  end