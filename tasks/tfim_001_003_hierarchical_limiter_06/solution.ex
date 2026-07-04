  test "reports the tier with the longest retry_after when multiple fail", %{hl: hl} do
    # Both tiers will saturate simultaneously at t=0.
    tiers = [{:per_sec, 3, 1_000}, {:per_min, 3, 60_000}]

    for _ <- 1..3, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Both tiers are at their limit. per_min's retry_after is ~60_000;
    # per_sec's is ~1_000. The caller has to wait on per_min.
    assert {:error, :rate_limited, :per_min, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    assert retry_after > 1_000
    assert retry_after <= 60_000
  end