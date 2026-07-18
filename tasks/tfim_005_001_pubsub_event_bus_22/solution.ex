  test "two subscriptions on same topic deliver exactly two copies", %{bus: bus} do
    {:ok, _ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, _ref2} = EventBus.subscribe(bus, "t", self())

    EventBus.publish(bus, "t", :dup)

    assert_receive {:event, "t", :dup}, 500
    assert_receive {:event, "t", :dup}, 500
    refute_receive {:event, "t", :dup}, 200
  end