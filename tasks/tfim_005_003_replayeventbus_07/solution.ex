  test "replayed events arrive before live events, in order", %{bus: bus} do
    for e <- [:a, :b, :c], do: ReplayEventBus.publish(bus, "t", e)

    {:ok, _ref} = ReplayEventBus.subscribe(bus, "t", self(), replay: :all)

    # Now publish one more live
    ReplayEventBus.publish(bus, "t", :d)

    assert [:a, :b, :c, :d] = drain("t")
  end