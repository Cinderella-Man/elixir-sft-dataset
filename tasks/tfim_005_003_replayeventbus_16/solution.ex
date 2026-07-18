  test "one pid with N subscriptions gets N copies per event", %{bus: bus} do
    {:ok, _r1} = ReplayEventBus.subscribe(bus, "t", self())
    {:ok, _r2} = ReplayEventBus.subscribe(bus, "t", self())

    ReplayEventBus.publish(bus, "t", :x)

    assert [:x, :x] = drain("t")
  end