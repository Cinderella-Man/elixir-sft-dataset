  test "set_history_size to 0 disables history", %{bus: bus} do
    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)
    :ok = ReplayEventBus.set_history_size(bus, "t", 0)
    assert [] = ReplayEventBus.history(bus, "t")

    ReplayEventBus.publish(bus, "t", 6)
    assert [] = ReplayEventBus.history(bus, "t")
  end