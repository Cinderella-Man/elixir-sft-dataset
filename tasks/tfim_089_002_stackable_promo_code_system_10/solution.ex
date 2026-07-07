  test "total discount never exceeds the order total" do
    {:ok, _} = StackablePromoCodes.create(%{code: "BIG", type: :fixed_amount, value: 5_000})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["BIG"], 3_000)
    assert find(r.applied, "BIG").discount == 3_000
    assert r.total_discount == 3_000
    assert r.final_total == 0
  end