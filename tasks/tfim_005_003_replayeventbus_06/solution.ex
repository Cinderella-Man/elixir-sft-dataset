  test "replay: N where N exceeds history size yields all events", %{bus: bus} do
    for e <- [:a, :b], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 100)

    assert [:a, :b] = drain("t")
  end