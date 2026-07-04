  test ":any clause is OR", %{bus: bus} do
    filter = [
      {:any,
       [
         {:eq, [:severity], :critical},
         {:eq, [:severity], :error}
       ]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{severity: :info})
    FilteredEventBus.publish(bus, "t", %{severity: :error})
    FilteredEventBus.publish(bus, "t", %{severity: :critical})
    FilteredEventBus.publish(bus, "t", %{severity: :warn})

    assert [%{severity: :error}, %{severity: :critical}] = drain("t")
  end