  test "replay: N delivers exactly the last N events in order", %{bus: bus} do
    for e <- [:a, :b, :c, :d, :e], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 2)

    assert [:d, :e] = drain("t")
  end