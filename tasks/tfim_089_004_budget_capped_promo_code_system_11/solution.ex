  test "max_uses is enforced ahead of budget exhaustion" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MU",
        type: :fixed_amount,
        value: 100,
        budget: 10_000,
        max_uses: 2
      })

    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:ok, 100} = BudgetPromoCodes.apply_code("MU", 10_000)
    assert {:error, :max_uses_exceeded} = BudgetPromoCodes.apply_code("MU", 10_000)
  end