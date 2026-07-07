  test "a percentage and a fixed code stack" do
    {:ok, _} = StackablePromoCodes.create(%{code: "PCT20", type: :percentage, value: 20})
    {:ok, _} = StackablePromoCodes.create(%{code: "FIX15", type: :fixed_amount, value: 1_500})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["PCT20", "FIX15"], 10_000)
    # 20% of 10_000 = 2_000; then 1_500 off the remaining 8_000
    assert r.total_discount == 3_500
    assert r.final_total == 6_500
    assert find(r.applied, "PCT20").discount == 2_000
    assert find(r.applied, "FIX15").discount == 1_500
    assert r.rejected == []
  end