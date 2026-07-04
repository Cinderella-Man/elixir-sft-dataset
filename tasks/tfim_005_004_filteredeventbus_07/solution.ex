  test "numeric clauses return false for non-numeric or missing values", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gt, [:n], 0}])

    FilteredEventBus.publish(bus, "t", %{n: 5})
    FilteredEventBus.publish(bus, "t", %{n: "five"})
    FilteredEventBus.publish(bus, "t", %{n: nil})
    FilteredEventBus.publish(bus, "t", %{other: 1})

    assert [%{n: 5}] = drain("t")
  end