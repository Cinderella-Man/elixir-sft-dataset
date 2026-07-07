  test "selects the correct tier by order total" do
    {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
    assert {:ok, 150} = TieredPromoCodes.apply_code("SPEND", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("SPEND", 5_000)
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("SPEND", 10_000)
    assert {:ok, 2_400} = TieredPromoCodes.apply_code("SPEND", 12_000)
  end