  test "free shipping draws from budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SB", type: :free_shipping, value: 999, budget: 1_500})

    assert {:ok, 999} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:ok, 501} = BudgetPromoCodes.apply_code("SB", 10_000)
    assert {:error, :budget_exhausted} = BudgetPromoCodes.apply_code("SB", 10_000)
  end