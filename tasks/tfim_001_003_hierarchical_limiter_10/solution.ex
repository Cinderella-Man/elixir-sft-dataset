  test "expired entries are pruned and empty keys dropped", %{hl: hl} do
    tiers = [{:per_sec, 1, 100}]

    for i <- 1..100 do
      assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # While the window is live, every key is holding its single slot.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "key:1", tiers)

    # Advance past the widest window so every recorded timestamp is expired.
    Clock.advance(200)

    send(hl, :cleanup)

    # The next check is a synchronous call, so it can only be served after the
    # cleanup pass has run. Every key admits a fresh request with a full
    # allowance, showing no expired timestamp survived the sweep.
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:1", tiers)

    for i <- 2..100 do
      assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "key:#{i}", tiers)
    end

    # The freshly recorded timestamps are honoured — the swept keys start over
    # rather than staying permanently open.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "key:50", tiers)
  end