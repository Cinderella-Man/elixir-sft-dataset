  test "preview reports :not_found and :below_min_order" do
    tiers = [%{threshold: 5_000, type: :percentage, value: 10}]
    {:ok, _} = TieredPromoCodes.create(%{code: "PVE", tiers: tiers})
    assert {:error, :not_found} = TieredPromoCodes.preview("NOPE", 5_000)
    assert {:error, :below_min_order} = TieredPromoCodes.preview("PVE", 1_000)
  end