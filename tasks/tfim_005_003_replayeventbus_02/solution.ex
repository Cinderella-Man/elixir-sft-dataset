  test "default subscribe has no replay — only live events", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :e1)
    ReplayEventBus.publish(bus, "t", :e2)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self())

    # Past events should NOT arrive
    assert [] = drain("t")

    ReplayEventBus.publish(bus, "t", :e3)
    assert [:e3] = drain("t")
  end