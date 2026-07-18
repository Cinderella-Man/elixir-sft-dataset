  test "list indexing via integer keys in path", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:items, 0], :apple}])

    FilteredEventBus.publish(bus, "t", %{items: [:banana, :apple]})
    FilteredEventBus.publish(bus, "t", %{items: [:apple]})
    FilteredEventBus.publish(bus, "t", %{items: []})

    assert [%{items: [:apple]}] = drain("t")
  end