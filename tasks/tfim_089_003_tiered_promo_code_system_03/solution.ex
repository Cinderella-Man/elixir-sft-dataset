  test "create rejects duplicates" do
    assert {:ok, _} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
    assert {:error, :already_exists} = TieredPromoCodes.create(%{code: "DUP", tiers: @pct_tiers})
  end