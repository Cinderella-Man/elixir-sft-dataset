  test "subscriber does not receive events for other topics", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.updated", %{id: 1})

    refute_receive {:event, "orders.updated", _}, 200
  end