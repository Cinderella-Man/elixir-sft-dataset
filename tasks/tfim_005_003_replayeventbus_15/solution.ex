  test "unsubscribe stops live delivery but leaves history intact", %{bus: bus} do
    {:ok, ref} = ReplayEventBus.subscribe(bus, "t", self())

    ReplayEventBus.publish(bus, "t", :a)
    assert [:a] = drain("t")

    :ok = ReplayEventBus.unsubscribe(bus, "t", ref)

    ReplayEventBus.publish(bus, "t", :b)
    assert [] = drain("t")

    # History includes both (publishes always update history)
    assert [:a, :b] = ReplayEventBus.history(bus, "t")
  end