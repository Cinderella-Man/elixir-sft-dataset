  test ":none clause excludes matching events", %{bus: bus} do
    filter = [
      {:none,
       [
         {:eq, [:source], :internal},
         {:eq, [:source], :debug}
       ]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{source: :user})
    FilteredEventBus.publish(bus, "t", %{source: :internal})
    FilteredEventBus.publish(bus, "t", %{source: :debug})
    FilteredEventBus.publish(bus, "t", %{source: :api})

    assert [%{source: :user}, %{source: :api}] = drain("t")
  end