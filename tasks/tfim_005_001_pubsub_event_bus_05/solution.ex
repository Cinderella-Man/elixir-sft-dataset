  test "wildcard * matches a single segment", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.created", :e1)
    EventBus.publish(bus, "orders.updated", :e2)

    assert_receive {:event, "orders.created", :e1}, 500
    assert_receive {:event, "orders.updated", :e2}, 500
  end