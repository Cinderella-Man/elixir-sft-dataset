  test "unbudgeted code dispenses the full discount every time" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "F5", type: :fixed_amount, value: 500})
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 500} = BudgetPromoCodes.apply_code("F5", 10_000)
    assert {:ok, 1_000} = BudgetPromoCodes.dispensed("F5")
  end