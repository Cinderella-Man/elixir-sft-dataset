  test "retry_after tracks the blocking tier's oldest-entry expiry", %{hl: hl} do
    tiers = [{:per_sec, 1, 1_000}]

    HierarchicalLimiter.check(hl, "k", tiers)
    Clock.advance(300)

    assert {:error, :rate_limited, :per_sec, retry_after} =
             HierarchicalLimiter.check(hl, "k", tiers)

    # Oldest (and only) entry is at t=0, expires at t=1000. We're at t=300.
    assert retry_after >= 600 and retry_after <= 800
  end