  test "exact topic matching only (no wildcards)", %{bus: bus} do
    {:ok, _} = ReplayEventBus.subscribe(bus, "orders.created", self())
    ReplayEventBus.publish(bus, "orders.updated", :x)

    assert [] = drain("orders.updated")
    assert [] = drain("orders.created")
  end