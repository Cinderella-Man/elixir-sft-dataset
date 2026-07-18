  test "cleanup drops topics with empty history and no subscribers", %{bus: bus} do
    # A per-topic history size override is part of the topic entry. Once the
    # sweep drops the topic, it is indistinguishable from a never-seen topic,
    # so the bus-wide default (10) governs the topic again.
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)

    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    send(bus, :cleanup)

    assert [] = ReplayEventBus.history(bus, "t")

    for i <- 1..15, do: ReplayEventBus.publish(bus, "t", i)

    assert Enum.to_list(6..15) == ReplayEventBus.history(bus, "t")
  end