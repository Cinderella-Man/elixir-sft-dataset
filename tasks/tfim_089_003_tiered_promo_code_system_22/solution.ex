  test "create rejects malformed thresholds and negative values" do
    neg_threshold = [%{threshold: -1, type: :percentage, value: 10}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NT", tiers: neg_threshold})

    float_threshold = [%{threshold: 1_000.0, type: :percentage, value: 10}]

    assert {:error, :invalid_tiers} =
             TieredPromoCodes.create(%{code: "FT", tiers: float_threshold})

    neg_fixed = [%{threshold: 0, type: :fixed_amount, value: -5}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NF", tiers: neg_fixed})

    bad_value = [%{threshold: 0, type: :percentage, value: "10"}]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "BV", tiers: bad_value})

    not_a_map = [%{threshold: 0, type: :percentage, value: 10}, :nope]
    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NM", tiers: not_a_map})
  end