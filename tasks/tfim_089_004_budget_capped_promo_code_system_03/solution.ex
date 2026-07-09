  test "create rejects duplicates and invalid type" do
    {:ok, _} = BudgetPromoCodes.create(%{code: "DUP", type: :percentage, value: 10})

    assert {:error, :already_exists} =
             BudgetPromoCodes.create(%{code: "DUP", type: :fixed_amount, value: 500})

    assert {:error, :invalid_type} =
             BudgetPromoCodes.create(%{code: "BAD", type: :bogus, value: 1})
  end