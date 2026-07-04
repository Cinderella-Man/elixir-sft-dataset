  test ":exists clause", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:exists, [:session_id]}])

    FilteredEventBus.publish(bus, "t", %{session_id: "abc"})
    FilteredEventBus.publish(bus, "t", %{})
    FilteredEventBus.publish(bus, "t", %{session_id: nil})

    assert [%{session_id: "abc"}] = drain("t")
  end