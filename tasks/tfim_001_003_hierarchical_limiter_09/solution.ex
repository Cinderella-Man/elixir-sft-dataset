  test "three-tier stack admits a sustainable request rate", %{hl: hl} do
    tiers = [
      {:per_sec, 10, 1_000},
      {:per_min, 100, 60_000},
      {:per_hour, 1_000, 3_600_000}
    ]

    # 10 requests at t=0 — saturates per_sec.
    for _ <- 1..10, do: HierarchicalLimiter.check(hl, "k", tiers)
    assert {:error, :rate_limited, :per_sec, _} = HierarchicalLimiter.check(hl, "k", tiers)

    # Advance a second, fire 10 more. Still under per_min (20/100) and per_hour (20/1000).
    Clock.advance(1_001)

    for i <- 1..10 do
      assert {:ok, remaining} = HierarchicalLimiter.check(hl, "k", tiers)
      assert remaining.per_sec == 10 - i
    end
  end