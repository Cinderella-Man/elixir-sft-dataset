  test "unbudgeted percentage discount" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "HALF", type: :percentage, value: 50})
    assert {:ok, 5_000} = BudgetPromoCodes.apply_code("HALF", 10_000)
    assert {:ok, :unlimited} = BudgetPromoCodes.remaining_budget("HALF")
  end