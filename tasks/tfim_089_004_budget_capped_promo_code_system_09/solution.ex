  test "unknown code returns :not_found" do
    assert {:error, :not_found} = BudgetPromoCodes.apply_code("NOPE", 10_000)
    assert {:error, :not_found} = BudgetPromoCodes.remaining_budget("NOPE")
    assert {:error, :not_found} = BudgetPromoCodes.dispensed("NOPE")
  end