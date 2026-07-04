  test ":in clause", %{bus: bus} do
    {:ok, _} =
      FilteredEventBus.subscribe(bus, "t", self(), [{:in, [:region], [:us_east, :us_west]}])

    FilteredEventBus.publish(bus, "t", %{region: :us_east})
    FilteredEventBus.publish(bus, "t", %{region: :eu})
    FilteredEventBus.publish(bus, "t", %{region: :us_west})

    assert [%{region: :us_east}, %{region: :us_west}] = drain("t")
  end