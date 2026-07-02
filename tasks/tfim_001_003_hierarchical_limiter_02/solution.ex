  test "with a single tier, behaves like a sliding window limiter", %{hl: hl} do
    tiers = [{:per_sec, 3, 1_000}]

    assert {:ok, %{per_sec: 2}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 1}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:ok, %{per_sec: 0}} = HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end