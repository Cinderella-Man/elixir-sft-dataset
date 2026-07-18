  test "an order total exactly equal to min_order_total applies the code" do
    {:ok, _} =
      StackablePromoCodes.create(%{
        code: "MIN5K",
        type: :fixed_amount,
        value: 500,
        min_order_total: 5_000
      })

    {:ok, _} = StackablePromoCodes.create(%{code: "NOMIN", type: :fixed_amount, value: 100})

    assert {:ok, r} = StackablePromoCodes.apply_codes(["MIN5K", "NOMIN"], 5_000)
    assert find(r.applied, "MIN5K").discount == 500
    assert find(r.applied, "NOMIN").discount == 100
    assert r.rejected == []
    assert r.final_total == 4_400
  end