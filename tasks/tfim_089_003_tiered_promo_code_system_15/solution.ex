  test "failed application (below min) does not consume a use" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "NC", tiers: tiers, max_uses: 1})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("NC", 1_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("NC", 5_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("NC", 5_000)
  end