  test "replay: 1 delivers exactly the single most recent event", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: 1)

    assert [:c] = drain("t")
  end