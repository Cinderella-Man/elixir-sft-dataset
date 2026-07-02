  test "replay: :all delivers every retained event in order", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    assert [:a, :b, :c] = drain("t")
  end