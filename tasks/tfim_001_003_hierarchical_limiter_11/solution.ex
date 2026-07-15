  test "cleanup keeps entries within the widest window ever seen for a key", %{hl: hl} do
    wide = [{:hour, 5, 3_600_000}]
    narrow = [{:sec, 5, 1_000}]

    # t=0: record one timestamp while the widest window seen is 1 hour.
    assert {:ok, %{hour: 4}} = HierarchicalLimiter.check(hl, "k", wide)

    # t=500: a narrow check still sees the t=0 entry (0.5s old) and records another.
    Clock.advance(500)
    assert {:ok, %{sec: 3}} = HierarchicalLimiter.check(hl, "k", narrow)

    # t=1600: both entries are ~1s old — far inside the widest window seen (1 hour),
    # so a cleanup pass must retain them rather than pruning to the 1s window.
    Clock.advance(1_100)
    send(hl, :cleanup)

    # The hour tier must still count both retained timestamps: 2 used + 1 new, so
    # remaining is 5 - 2 - 1 = 2. If cleanup wrongly pruned to the 1s window the
    # key would be dropped and this would report hour: 4.
    assert {:ok, %{hour: 2}} = HierarchicalLimiter.check(hl, "k", wide)
  end