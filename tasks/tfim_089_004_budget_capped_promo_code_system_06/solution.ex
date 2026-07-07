  test "fixed-amount budget clips the final application and then exhausts" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "FB", type: :fixed_amount, value: 5_000, budget: 8_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 3_000} = BudgetPromoCodes.remaining_budget("FB")
    # clipped to remaining 3_000
    assert {:ok, 3_000} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 0} = BudgetPromoCodes.remaining_budget("FB")
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("FB", 10_000)
    assert {:ok, 8_000} = BudgetPromoCodes.dispensed("FB")
  end