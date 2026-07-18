  test "fixed amount discount is capped at the order total" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "CAP", type: :fixed_amount, value: 5_000})
    assert {:ok, 3_000} = BudgetPromoCodes.apply_code("CAP", 3_000)
    assert {:ok, 0} = BudgetPromoCodes.apply_code("CAP", 0)
    assert {:ok, 3_000} = BudgetPromoCodes.dispensed("CAP")
  end