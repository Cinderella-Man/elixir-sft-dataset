  test "no event is missed or duplicated between replay and live", %{bus: bus} do
    # Publish 2 events
    ReplayEventBus.publish(bus, "t", :a)
    ReplayEventBus.publish(bus, "t", :b)

    # Subscribe asking for replay
    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    # Publish one more — should arrive exactly once (live), NOT in replay
    ReplayEventBus.publish(bus, "t", :c)

    # Total: 3 events, each exactly once
    assert [:a, :b, :c] = drain("t")
  end