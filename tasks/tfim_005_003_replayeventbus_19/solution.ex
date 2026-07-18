  test "cleanup keeps topics with subscribers even if history is empty", %{bus: bus} do
    {:ok, _} = ReplayEventBus.subscribe(bus, "t", self())
    :ok = ReplayEventBus.set_history_size(bus, "t", 3)
    # No events published, history empty
    Clock.advance(15_000)

    send(bus, :cleanup)

    assert [] = ReplayEventBus.history(bus, "t")

    # The topic survived the sweep along with its subscriber: live events are
    # still delivered to it, and its per-topic size override still applies.
    for i <- 1..5, do: ReplayEventBus.publish(bus, "t", i)

    assert [1, 2, 3, 4, 5] = drain("t")
    assert [3, 4, 5] = ReplayEventBus.history(bus, "t")
  end