  test "combined AND of top-level with nested :any", %{bus: bus} do
    filter = [
      {:eq, [:type], :alert},
      {:any, [{:eq, [:level], :high}, {:eq, [:level], :critical}]}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{type: :alert, level: :low})
    FilteredEventBus.publish(bus, "t", %{type: :alert, level: :high})
    FilteredEventBus.publish(bus, "t", %{type: :note, level: :critical})

    assert [%{type: :alert, level: :high}] = drain("t")
  end