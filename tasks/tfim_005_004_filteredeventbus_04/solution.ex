  test ":eq clause filters on nested path", %{bus: bus} do
    {:ok, _} = FilteredEventBus.subscribe(bus, "t", self(), [{:eq, [:user, :role], :admin}])

    FilteredEventBus.publish(bus, "t", %{user: %{role: :admin}})
    FilteredEventBus.publish(bus, "t", %{user: %{role: :guest}})
    FilteredEventBus.publish(bus, "t", %{user: %{role: :admin}, extra: 1})

    assert [
             %{user: %{role: :admin}},
             %{user: %{role: :admin}, extra: 1}
           ] = drain("t")
  end