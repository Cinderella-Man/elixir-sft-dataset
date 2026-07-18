  test "a retry landing exactly on the budget boundary is still scheduled", %{rw: _rw} do
    {:ok, rw2} = BudgetRetryWorker.start_link(clock: &Clock.now/0, random: &MinRandom.rand/2)
    start_supervised!({Counter, 0})

    func = fn ->
      if Counter.increment_and_get() == 1 do
        Clock.advance(900)
        {:error, :boom}
      else
        {:ok, :done}
      end
    end

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw2, func, budget_ms: 1_000, base_delay_ms: 100)
      end)

    # elapsed (900) + capped delay (100) == budget (1000). The documented rule
    # rejects a retry only when the sum WOULD EXCEED the budget — equality does
    # not exceed, so this retry must run and the call must succeed.
    Process.sleep(20)
    Clock.advance(100)
    assert {:ok, :done} = Task.await(task, 5_000)
  end