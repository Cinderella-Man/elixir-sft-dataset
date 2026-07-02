  test "subscriber receives published event", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.created", self())

    EventBus.publish(bus, "orders.created", %{id: 1})

    assert_receive {:event, "orders.created", %{id: 1}}, 500
  end