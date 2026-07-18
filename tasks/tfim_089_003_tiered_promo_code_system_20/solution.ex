  test "expired window outranks a below-minimum order total" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]

    {:ok, _} =
      TieredPromoCodes.create(%{code: "EXPLOW", tiers: tiers, valid_until: @past})

    assert {:error, :expired} = TieredPromoCodes.apply_code("EXPLOW", 1_000)

    {:ok, _} =
      TieredPromoCodes.create(%{code: "SOONLOW", tiers: tiers, valid_from: @future})

    assert {:error, :not_yet_valid} = TieredPromoCodes.apply_code("SOONLOW", 1_000)
  end