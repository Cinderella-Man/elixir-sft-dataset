  test "user_id does not grant a separate budget or extra uses" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "UID",
        type: :fixed_amount,
        value: 600,
        budget: 1_000,
        max_uses: 2
      })

    assert {:ok, 600} = BudgetPromoCodes.apply_code("UID", 10_000, user_id: "alice")
    # second user draws from the SAME shared budget, clipped to what is left
    assert {:ok, 400} = BudgetPromoCodes.apply_code("UID", 10_000, user_id: "bob")
    assert {:ok, 0} = BudgetPromoCodes.remaining_budget("UID")
    # total uses are counted across users, not per user
    assert {:error, :max_uses_exceeded} =
             BudgetPromoCodes.apply_code("UID", 10_000, user_id: "carol")

    assert {:ok, 1_000} = BudgetPromoCodes.dispensed("UID")
  end