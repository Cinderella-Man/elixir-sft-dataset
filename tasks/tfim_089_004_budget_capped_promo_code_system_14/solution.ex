  test "order total exactly equal to min_order_total is accepted" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "EQ",
        type: :fixed_amount,
        value: 500,
        budget: 1_000,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("EQ", 4_999)
    assert {:ok, 500} = BudgetPromoCodes.apply_code("EQ", 5_000)
    assert {:ok, 500} = BudgetPromoCodes.remaining_budget("EQ")
    assert {:ok, 500} = BudgetPromoCodes.dispensed("EQ")
  end