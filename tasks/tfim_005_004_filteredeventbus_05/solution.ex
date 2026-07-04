  test ":neq clause", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:neq, [:status], :ignored}])

    FilteredEventBus.publish(bus, "t", %{status: :ok})
    FilteredEventBus.publish(bus, "t", %{status: :ignored})

    assert [%{status: :ok}] = drain("t")
  end