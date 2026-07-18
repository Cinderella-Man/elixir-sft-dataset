  test "single * pattern matches exactly one segment", %{bus: bus} do
    {:ok, _ref} = EventBus.subscribe(bus, "*", self())

    EventBus.publish(bus, "orders", :one_seg)
    EventBus.publish(bus, "orders.created", :two_seg)

    assert_receive {:event, "orders", :one_seg}, 500
    refute_receive {:event, "orders.created", _}, 200
  end