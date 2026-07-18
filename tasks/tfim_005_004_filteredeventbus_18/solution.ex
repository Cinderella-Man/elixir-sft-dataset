  test "publish returns count of subscribers that received the event", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 100}])

    assert {:ok, 2} = FilteredEventBus.publish(bus, "t", %{n: 500})
    assert {:ok, 1} = FilteredEventBus.publish(bus, "t", %{n: 50})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{n: -5})

    _ = drain("t")
  end