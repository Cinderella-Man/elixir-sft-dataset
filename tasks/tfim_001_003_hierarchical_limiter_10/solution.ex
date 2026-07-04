  test "expired entries are pruned and empty keys dropped", %{hl: hl} do
    tiers = [{:per_sec, 1, 100}]

    for i <- 1..100 do
      HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # Advance past the widest window
    Clock.advance(200)

    send(hl, :cleanup)
    :sys.get_state(hl)

    state = :sys.get_state(hl)
    assert map_size(state.keys) == 0

    # New requests work fresh
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:1", tiers)
  end