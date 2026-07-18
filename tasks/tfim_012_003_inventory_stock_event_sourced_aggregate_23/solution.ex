  test "full command sequence produces correct state and event history", %{agg: agg} do
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:register, "Bolt", "BLT-100"})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:receive_stock, 500})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:receive_stock, 300})
    {:error, :insufficient_stock} = InventoryAggregate.execute(agg, "a", {:ship_stock, 900})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:ship_stock, 150})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:adjust, -50})
    {:ok, _} = InventoryAggregate.execute(agg, "a", {:ship_stock, 600})

    state = InventoryAggregate.state(agg, "a")
    assert state.name == "Bolt"
    assert state.sku == "BLT-100"
    assert state.quantity_on_hand == 0
    assert state.status == :registered

    events = InventoryAggregate.events(agg, "a")
    # 6 successful commands = 6 events
    assert length(events) == 6

    types = Enum.map(events, & &1.type)

    assert types == [
             :product_registered,
             :stock_received,
             :stock_received,
             :stock_shipped,
             :stock_adjusted,
             :stock_shipped
           ]
  end