  test "history is bounded by default_history_size", %{bus: bus} do
    for i <- 1..15, do: ReplayEventBus.publish(bus, "t", i)

    # default_history_size is 10 → history keeps the last 10
    assert [6, 7, 8, 9, 10, 11, 12, 13, 14, 15] = ReplayEventBus.history(bus, "t")
  end