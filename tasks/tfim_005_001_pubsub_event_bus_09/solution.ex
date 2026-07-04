  test "wildcard in the middle: orders.*.completed", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*.completed", self())

    EventBus.publish(bus, "orders.42.completed", :yes)
    EventBus.publish(bus, "orders.99.completed", :also_yes)
    EventBus.publish(bus, "orders.completed", :nope)
    EventBus.publish(bus, "orders.42.shipped", :nope2)

    assert_receive {:event, "orders.42.completed", :yes}, 500
    assert_receive {:event, "orders.99.completed", :also_yes}, 500
    refute_receive {:event, "orders.completed", _}, 200
    refute_receive {:event, "orders.42.shipped", _}, 200
  end