  test "below minimum order does not touch budget" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "MIN",
        type: :fixed_amount,
        value: 500,
        budget: 1_000,
        min_order_total: 5_000
      })

    assert {:error, :below_min_order} = BudgetPromoCodes.apply_code("MIN", 3_000)
    assert {:ok, 1_000} = BudgetPromoCodes.remaining_budget("MIN")
    assert {:ok, 0} = BudgetPromoCodes.dispensed("MIN")
  end