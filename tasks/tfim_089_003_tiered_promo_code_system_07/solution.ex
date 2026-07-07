  test "create rejects an unknown tier type" do
    tiers = [%{threshold: 0, type: :bogus, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADT", tiers: tiers})
  end