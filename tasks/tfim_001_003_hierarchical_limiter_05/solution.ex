  test "rejected requests do not consume budget on any tier", %{hl: hl} do
    tiers = [{:per_sec, 2, 1_000}, {:per_min, 10, 60_000}]

    assert {:ok, %{per_sec: 1, per_min: 9}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0, per_min: 8}} = HierarchicalLimiter.check(hl, "k", tiers)

    # Blast a bunch of rejections against per_sec.
    for _ <- 1..10 do
      assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
    end

    # Advance past the per_sec window. per_min must show only 2 consumed,
    # not 12 — rejections shouldn't count.
    Clock.advance(1_001)
    assert {:ok, %{per_min: 7}} = HierarchicalLimiter.check(hl, "k", tiers)
  end