  test "preview returns discount and tier index without consuming a use" do
    {:ok, _} = TieredPromoCodes.create(%{code: "PV", tiers: @pct_tiers, max_uses: 1})
    assert {:ok, 500, 1} = TieredPromoCodes.preview("PV", 5_000)
    assert {:ok, 2_000, 2} = TieredPromoCodes.preview("PV", 10_000)
    # the single use is still available
    assert {:ok, 2_000} = TieredPromoCodes.apply_code("PV", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("PV", 10_000)
  end