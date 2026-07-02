  test "exact-topic matching only (no wildcards)", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "orders.created", self())
    FilteredEventBus.publish(bus, "orders.updated", %{})

    assert [] = drain("orders.updated")
  end