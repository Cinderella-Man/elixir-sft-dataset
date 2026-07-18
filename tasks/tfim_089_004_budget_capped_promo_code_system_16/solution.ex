  test "failed applications do not consume a use" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "FAIL",
        type: :fixed_amount,
        value: 100,
        budget: 1_000,
        max_uses: 1,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("FAIL", 100)
    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("FAIL", 4_999, user_id: "u1")
    # the single permitted use must still be available
    assert {:ok, 100} = BudgetPromoCodes.apply_code("FAIL", 5_000)
    assert {:error, :max_uses_exceeded} = BudgetPromoCodes.apply_code("FAIL", 5_000)
    assert {:ok, 100} = BudgetPromoCodes.dispensed("FAIL")
    assert {:ok, 900} = BudgetPromoCodes.remaining_budget("FAIL")
  end