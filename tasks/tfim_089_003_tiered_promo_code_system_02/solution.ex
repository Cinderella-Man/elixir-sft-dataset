  test "create accepts a valid tiered code" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "SPEND", tiers: @pct_tiers})
  end