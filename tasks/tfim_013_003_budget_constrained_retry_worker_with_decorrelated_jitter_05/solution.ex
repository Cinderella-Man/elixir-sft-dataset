  test "returns budget_exhausted when time runs out", %{rw: rw} do
    func = fail_then_succeed(100, :never)

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 250,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # Initial attempt fails at t=0. Next delay = 100.
    # elapsed(0) + 100 <= 250 → schedule retry
    Process.sleep(20)
    Clock.advance(100)

    # Attempt 2 at t=100 fails. Next delay = 100.
    # elapsed(100) + 100 = 200 <= 250 → schedule retry
    Process.sleep(20)
    Clock.advance(100)

    # Attempt 3 at t=200 fails. Next delay = 100.
    # elapsed(200) + 100 = 300 > 250 → budget exhausted
    Process.sleep(20)

    assert {:error, :budget_exhausted, :boom, attempts} = Task.await(task, 5_000)
    assert attempts == 3
  end