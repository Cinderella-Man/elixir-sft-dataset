  test "fixed-amount tiers cap at the order total" do
    tiers = [%{threshold: 0, type: :fixed_amount, value: 1_500}]
    {:ok, _} = TieredPromoCodes.create(%{code: "F15", tiers: tiers})
    assert {:ok, 1_000} = TieredPromoCodes.apply_code("F15", 1_000)
    assert {:ok, 1_500} = TieredPromoCodes.apply_code("F15", 10_000)
  end