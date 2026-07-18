  test "each discount is capped at the remaining total in prompt order" do
    {:ok, _} = StackablePromoCodes.create(%{code: "P90", type: :percentage, value: 90})
    {:ok, _} = StackablePromoCodes.create(%{code: "SH", type: :free_shipping, value: 500})
    {:ok, _} = StackablePromoCodes.create(%{code: "FA", type: :fixed_amount, value: 400})
    {:ok, _} = StackablePromoCodes.create(%{code: "FB", type: :fixed_amount, value: 300})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["FA", "SH", "FB", "P90"], 1_000)
    assert find(r.applied, "P90").discount == 900
    assert find(r.applied, "P90").type == :percentage
    assert find(r.applied, "SH").discount == 100
    assert find(r.applied, "FA").discount == 0
    assert find(r.applied, "FB").discount == 0
    assert r.total_discount == 1_000
    assert r.final_total == 0
    assert r.rejected == []
  end