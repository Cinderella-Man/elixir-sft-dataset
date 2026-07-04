  test "wildcard * does not match multiple segments", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders.items.created", :nope)

    refute_receive {:event, "orders.items.created", _}, 200
  end