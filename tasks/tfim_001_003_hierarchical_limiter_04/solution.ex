  test "tighter outer tier can reject even when inner tier has capacity", %{hl: hl} do
    # 10/sec AND 15/min — the minute cap is the binding constraint across bursts.
    tiers = [{:per_sec, 10, 1_000}, {:per_min, 15, 60_000}]

    # 10 requests in the first second
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)

    # Advance 1.5 seconds: per_sec is clear, per_min has 10 and allows 5 more.
    Clock.advance(1_500)
    for _ <- 1..5, do: HierarchicalLimiter.check(hl, "k", tiers)

    # 16th request: per_sec has headroom but per_min is full → rejected by per_min.
    assert {:error, :rate_limited, :per_min, _} = HierarchicalLimiter.check(hl, "k", tiers)
  end