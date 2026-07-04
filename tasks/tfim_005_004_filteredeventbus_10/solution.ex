  test "multiple clauses at top level are AND-ed", %{bus: bus} do
    filter = [
      {:eq, [:type], :purchase},
      {:gt, [:amount], 100}
    ]

    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), filter)

    FilteredEventBus.publish(bus, "t", %{type: :purchase, amount: 50})
    FilteredEventBus.publish(bus, "t", %{type: :refund, amount: 500})
    FilteredEventBus.publish(bus, "t", %{type: :purchase, amount: 500})

    assert [%{type: :purchase, amount: 500}] = drain("t")
  end