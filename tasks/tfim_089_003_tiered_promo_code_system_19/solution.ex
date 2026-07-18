  test "preview ignores the time window and exhausted usage limits" do
    {:ok, _} =
      TieredPromoCodes.create(%{code: "PVW", tiers: @pct_tiers, valid_until: @past, max_uses: 1})

    assert {:error, :expired} = TieredPromoCodes.apply_code("PVW", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVW", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVU", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PVU", 10_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PVU", 10_000)

    {:ok, _} = TieredPromoCodes.create(%{code: "PVF", tiers: @pct_tiers, valid_from: @future})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PVF", 5_000)
  end