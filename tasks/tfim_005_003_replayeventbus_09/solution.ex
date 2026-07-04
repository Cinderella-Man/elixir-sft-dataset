  test "set_history_size overrides the default", %{bus: bus} do
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)

    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)

    assert [3, 4, 5] = ReplayEventBus.history(bus, "t")
  end