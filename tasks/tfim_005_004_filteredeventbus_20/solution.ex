  test "unsubscribe removes a specific subscription", %{bus: bus} do
    {:ok, r1} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])
    {:ok, _r2} = FilteredEventBus.subscribe(bus, "t", self(), [{:lt, [:n], 0}])

    :ok = FilteredEventBus.unsubscribe(bus, "t", r1)

    FilteredEventBus.publish(bus, "t", %{n: 5})
    assert [] = drain("t")

    FilteredEventBus.publish(bus, "t", %{n: -5})
    assert [%{n: -5}] = drain("t")
  end