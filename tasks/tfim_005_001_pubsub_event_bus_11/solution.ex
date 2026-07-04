  test "unsubscribe stops delivery", %{bus: bus} do
    {:ok, ref} = EventBus.subscribe(bus, "t", self())

    EventBus.publish(bus, "t", :before)
    assert_receive {:event, "t", :before}, 500

    :ok = EventBus.unsubscribe(bus, "t", ref)

    EventBus.publish(bus, "t", :after)
    refute_receive {:event, "t", :after}, 200
  end