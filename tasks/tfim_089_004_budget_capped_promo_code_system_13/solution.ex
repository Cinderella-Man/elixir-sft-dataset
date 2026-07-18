  test "clock advancing past valid_until exhausts nothing but expires the code" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "WIN",
        type: :fixed_amount,
        value: 500,
        budget: 5_000,
        valid_until: ~U[2026-06-10 00:00:00Z]
      })

    assert {:ok, 500} = BudgetPromoCodes.apply_code("WIN", 10_000)
    Clock.set(~U[2026-06-11 00:00:00Z])
    assert {:error, :expired} = BudgetPromoCodes.apply_code("WIN", 10_000)
    assert {:ok, 4_500} = BudgetPromoCodes.remaining_budget("WIN")
  end