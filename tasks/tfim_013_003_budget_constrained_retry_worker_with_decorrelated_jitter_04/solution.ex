  test "retries and succeeds within the time budget", %{rw: rw} do
    func = fail_then_succeed(2, :recovered)

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 10_000,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # With MinRandom, decorrelated jitter returns base_delay each time
    # retry 1: delay = min(100, 10000) = 100
    Process.sleep(20)
    Clock.advance(100)
    # retry 2: prev_delay=100, delay = min(100, 10000) = 100
    Process.sleep(20)
    Clock.advance(100)

    assert {:ok, :recovered} = Task.await(task, 5_000)
    assert Counter.get() == 3
  end