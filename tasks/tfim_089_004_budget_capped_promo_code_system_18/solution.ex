  test "percentage discount rounds fractional cents" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "RND", type: :percentage, value: 10})
    # 105 * 10 / 100 = 10.5 -> 11
    assert {:ok, 11} = BudgetPromoCodes.apply_code("RND", 105)

    {:ok, _} = BudgetPromoCodes.create(%{code: "RND3", type: :percentage, value: 33})
    # 101 * 33 / 100 = 33.33 -> 33
    assert {:ok, 33} = BudgetPromoCodes.apply_code("RND3", 101)
    assert {:ok, 11} = BudgetPromoCodes.dispensed("RND")
  end