  test "create rejects an out-of-range percentage" do
    tiers = [%{threshold: 0, type: :percentage, value: 150}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BADP", tiers: tiers})
  end