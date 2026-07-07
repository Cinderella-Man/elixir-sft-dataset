  test "create rejects non-ascending thresholds" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 5_000, type: :percentage, value: 20}
    ]

    assert {:error, :invalid_tiers} = TieredPromoCodes.create(%{code: "NA", tiers: tiers})
  end