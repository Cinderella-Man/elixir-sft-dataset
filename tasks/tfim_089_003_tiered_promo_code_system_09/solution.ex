  test "order below the smallest threshold returns :below_min_order" do
    tiers = [
      %{threshold: 5_000, type: :percentage, value: 10},
      %{threshold: 10_000, type: :percentage, value: 20}
    ]

    {:ok, _} = TieredPromoCodes.create(%{code: "HIGH", tiers: tiers})
    assert {:error, :below_min_order} = TieredPromoCodes.apply_code("HIGH", 3_000)
    assert {:ok, 500} = TieredPromoCodes.apply_code("HIGH", 5_000)
  end