  test "create accepts a valid code" do
    assert {:ok, _} =
             BudgetPromoCodes.create(%{code: "B", type: :fixed_amount, value: 500, budget: 1_000})
  end