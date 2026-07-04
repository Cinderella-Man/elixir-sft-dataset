  test "exact subscription only matches exact topic", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.created", :match)
    EventBus.publish(bus, "orders.updated", :no_match)

    assert_receive {:event, "orders.created", :match}, 500
    refute_receive {:event, "orders.updated", _}, 200
  end