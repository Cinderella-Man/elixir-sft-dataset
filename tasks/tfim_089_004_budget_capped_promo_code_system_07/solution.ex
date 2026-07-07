  test "percentage budget clips a large discount" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "PB", type: :percentage, value: 50, budget: 6_000})

    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("PB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("PB", 10_000)
  end