  test "request is allowed only when every tier has capacity", %{hl: hl} do
    tiers = [{:per_sec, 5, 1_000}, {:per_min, 10, 60_000}]

    # Burn through the per_sec tier (5 requests at t=0).
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 6th request is rejected by per_sec even though per_min still has headroom.
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance to t=1001, per_sec clears, per_min still holds 5 of 10.
    Clock.advance(1_001)
    assert {:ok, %{per_sec: 4, per_min: 4}} = HierarchicalLimiter.check(hl, "k", tiers)
  end