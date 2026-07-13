  test "elapsed time is measured against the recorded start timestamp", %{rw: _rw} do
    {:ok, rw2} = BudgetRetryWorker.start_link(clock: &Clock.now/0, random: &MinRandom.rand/2)
    Clock.advance(50_000)
    func = fail_then_succeed(1, :done)

    task = Task.async(fn -> BudgetRetryWorker.execute(rw2, func, []) end)

    Process.sleep(20)
    Clock.advance(100)

    # started_at = 50_000: one 100 ms retry keeps elapsed tiny relative to the
    # default 30_000 ms budget. A worker comparing against anything other than
    # the recorded start would see a huge elapsed and exhaust immediately.
    assert {:ok, :done} = Task.await(task, 5_000)
  end