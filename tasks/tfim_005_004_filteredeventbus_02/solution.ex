  test "empty filter matches every event on the topic", %{bus: bus} do
    {:ok, _ref} = FilteredEventBus.subscribe(bus, "t", self())

    FilteredEventBus.publish(bus, "t", %{a: 1})
    FilteredEventBus.publish(bus, "t", %{a: 2})

    assert [%{a: 1}, %{a: 2}] = drain("t")
  end