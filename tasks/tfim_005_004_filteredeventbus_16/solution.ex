  test "invalid filters are rejected at subscribe", %{bus: bus} do
    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:unknown_op, [:a], 1}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:eq, "not_a_list", 1}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:any, []}])

    assert {:error, :invalid_filter} =
             FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [3.14], 1}])
  end