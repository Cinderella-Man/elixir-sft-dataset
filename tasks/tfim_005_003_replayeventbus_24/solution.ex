  test "history/2 returns [] for a topic never published or subscribed", %{bus: bus} do
    assert [] = ReplayEventBus.history(bus, "never.seen.topic")
  end