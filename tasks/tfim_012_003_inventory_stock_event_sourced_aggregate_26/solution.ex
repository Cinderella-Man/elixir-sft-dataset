  test "negative adjustment landing on exactly zero succeeds", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 10})

    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:adjust, -10})
    assert event.type == :stock_adjusted
    assert InventoryAggregate.state(agg, "prod:1").quantity_on_hand == 0
  end