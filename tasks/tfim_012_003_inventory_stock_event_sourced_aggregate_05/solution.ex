  test "receive_stock increases quantity_on_hand", %{agg: agg} do
    InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert {:ok, [event]} = InventoryAggregate.execute(agg, "prod:1", {:receive_stock, 100})
    assert event.type == :stock_received

    state = InventoryAggregate.state(agg, "prod:1")
    assert state.quantity_on_hand == 100
  end