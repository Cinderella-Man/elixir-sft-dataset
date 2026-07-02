  test "create rejects an empty tier list" do
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "E", tiers: []})
  end