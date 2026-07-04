  test "*.* matches any two-segment topic", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "*.*", self())

    EventBus.publish(bus, "orders.created", :e1)
    EventBus.publish(bus, "users.deleted", :e2)

    assert_receive {:event, "orders.created", :e1}, 500
    assert_receive {:event, "users.deleted", :e2}, 500

    # Should NOT match single or triple segments
    EventBus.publish(bus, "orders", :nope)
    EventBus.publish(bus, "a.b.c", :nope2)

    refute_receive {:event, "orders", _}, 200
    refute_receive {:event, "a.b.c", _}, 200
  end