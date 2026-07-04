  test "different keys have independent budgets across all tiers", %{hl: hl} do
    tiers = [{:per_sec, 2, 1_000}, {:per_min, 5, 60_000}]

    # Exhaust per_sec for "a"
    HierarchicalLimiter.check(hl, "a", tiers)
    HierarchicalLimiter.check(hl, "a", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "a", tiers)

    # "b" is unaffected
    assert {:ok, %{per_sec: 1, per_min: 4}} = HierarchicalLimiter.check(hl, "b", tiers)
    assert {:ok, %{per_sec: 0, per_min: 3}} = HierarchicalLimiter.check(hl, "b", tiers)
  end