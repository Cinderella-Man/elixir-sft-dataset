  test "returns immediately when function succeeds on first try", %{rw: rw} do
    func = fn -> {:ok, 42} end

    assert {:ok, 42} =
             BudgetRetryWorker.execute(rw, func,
               budget_ms: 10_000,
               base_delay_ms: 100
             )
  end