  test "register produces a :product_registered event", %{agg: agg} do
    assert {:ok, [event]} =
             InventoryAggregate.execute(agg, "prod:1", {:register, "Widget", "WDG-001"})
    assert event.type == :product_registered
  end