  test "time window is enforced with inclusive boundaries" do
    {:ok, _} =
      BudgetPromoCodes.create(%{code: "SOON", type: :percentage, value: 10, valid_from: @future})

    assert {:error, :not_yet_valid} = BudgetPromoCodes.apply_code("SOON", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{code: "OLD", type: :percentage, value: 10, valid_until: @past})

    assert {:error, :expired} = BudgetPromoCodes.apply_code("OLD", 10_000)

    {:ok, _} =
      BudgetPromoCodes.create(%{
        code: "EDGE",
        type: :percentage,
        value: 10,
        valid_from: Clock.base(),
        valid_until: Clock.base()
      })

    assert {:ok, 1_000} = BudgetPromoCodes.apply_code("EDGE", 10_000)
  end