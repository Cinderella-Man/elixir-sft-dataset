  test "max_uses is enforced" do
    {:ok, _} = TieredPromoCodes.create(%{code: "TWICE", tiers: @pct_tiers, max_uses: 2})
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:ok, _} = TieredPromoCodes.apply_code("TWICE", 10_000)
    assert {:error, :max_uses_exceeded} = TieredPromoCodes.apply_code("TWICE", 10_000)
  end