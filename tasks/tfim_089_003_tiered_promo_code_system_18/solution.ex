  test "create rejects a non-binary code with :invalid_code" do
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{code: :atom, tiers: @pct_tiers})
    assert {:error, :invalid_code} = TieredPromoCodes.create(%{tiers: @pct_tiers})
  end