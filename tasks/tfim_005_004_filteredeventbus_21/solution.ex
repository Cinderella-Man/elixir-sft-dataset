  test ":gte matches at and above the boundary, not below", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:gte, [:amount], 1000}])

    for a <- [999, 1000, 1001], do: FilteredEventBus.publish(bus, "t", %{amount: a})

    assert [%{amount: 1000}, %{amount: 1001}] = drain("t")
  end