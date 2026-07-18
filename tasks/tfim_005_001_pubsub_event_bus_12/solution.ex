  test "unsubscribe one subscription doesn't affect another on same topic", %{bus: bus} do
    {:ok, ref1} = EventBus.subscribe(bus, "t", self())
    {:ok, _ref2} = EventBus.subscribe(bus, "t", self())

    :ok = EventBus.unsubscribe(bus, "t", ref1)

    EventBus.publish(bus, "t", :hi)

    # Should receive exactly one copy (from _ref2)
    assert_receive {:event, "t", :hi}, 500
    refute_receive {:event, "t", :hi}, 200
  end