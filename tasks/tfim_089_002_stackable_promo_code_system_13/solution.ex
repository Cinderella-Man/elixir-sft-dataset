  test "below-minimum code is rejected but others apply" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        min_order_total: 5_000
      })

    {:ok, _} = StackablePromoCodes.create(%{code: "ANY", type: :fixed_amount, value: 250})
    assert {:ok, r} = StackablePromoCodes.apply_codes(["MIN", "ANY"], 3_000)
    assert find(r.rejected, "MIN").reason == :below_min_order
    assert find(r.applied, "ANY").discount == 250
  end