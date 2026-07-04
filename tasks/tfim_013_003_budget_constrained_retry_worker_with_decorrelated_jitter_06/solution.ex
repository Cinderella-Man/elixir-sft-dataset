  test "zero budget means only one attempt", %{rw: rw} do
    func = fail_then_succeed(5, :nope)

    assert {:error, :budget_exhausted, :boom, 1} =
             BudgetRetryWorker.execute(rw, func,
               budget_ms: 0,
               base_delay_ms: 100
             )
  end