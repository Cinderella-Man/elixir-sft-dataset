  test "cleanup evicts expired history", %{bus: bus} do
    ReplayEventBus.publish(bus, "t", :old)
    Clock.advance(15_000)

    send(bus, :cleanup)

    # history/2 is a synchronous call, so it can only be served after the
    # bus has finished handling the :cleanup sweep queued before it.
    assert [] = ReplayEventBus.history(bus, "t")
  end