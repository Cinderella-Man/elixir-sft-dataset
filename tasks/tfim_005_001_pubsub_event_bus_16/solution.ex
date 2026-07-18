  test "publish matches both exact and wildcard subscribers", %{bus: bus} do
    {:ok, _} = EventBus.subscribe(bus, "orders.created", self())
    {:ok, _} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.created", :boom)

    # Should receive two copies: one from exact, one from wildcard
    assert_receive {:event, "orders.created", :boom}, 500
    assert_receive {:event, "orders.created", :boom}, 500
  end