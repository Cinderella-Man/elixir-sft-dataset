  test "wildcard * does not match zero segments", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "orders.*", self())

    EventBus.publish(bus, "orders", :nope)

    refute_receive {:event, "orders", _}, 200
  end