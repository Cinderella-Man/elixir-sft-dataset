  test "deeply nested missing path returns nil, not crash", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:a, :b, :c], :x}])

    # No crash, no match
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{a: 1})
    assert {:ok, 0} = FilteredEventBus.publish(bus, "t", %{a: %{b: nil}})
    assert {:ok, 1} = FilteredEventBus.publish(bus, "t", %{a: %{b: %{c: :x}}})
  end