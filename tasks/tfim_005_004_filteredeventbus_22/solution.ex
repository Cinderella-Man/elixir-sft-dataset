  test ":lte matches at and below the boundary, not above", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:lte, [:amount], 1000}])

    for a <- [999, 1000, 1001], do: FilteredEventBus.publish(bus, "t", %{amount: a})

    assert [%{amount: 999}, %{amount: 1000}] = drain("t")
  end