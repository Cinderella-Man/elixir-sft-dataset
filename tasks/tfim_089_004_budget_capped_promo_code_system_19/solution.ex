  test "earlier checks win over later failures for the same application" do
    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "PREC",
        type: :fixed_amount,
        value: 100,
        budget: 0,
        max_uses: 0,
        min_order_total: 10_000,
        valid_until: @past
      })

    assert {:error, :expired} = BudgetPromoCodes.apply_code("PREC", 1)

    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "PREC2",
        type: :percentage,
        value: 10,
        budget: 0,
        max_uses: 0,
        min_order_total: 10_000,
        valid_from: @future,
        valid_until: @past
      })

    assert {:error, :not_yet_valid} = BudgetPromoCodes.apply_code("PREC2", 1)
  end