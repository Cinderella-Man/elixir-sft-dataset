  test "attempt count reflects all tries made", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw, func,
          budget_ms: 350,
          base_delay_ms: 100,
          max_delay_ms: 10_000
        )
      end)

    # With MinRandom: delay is always base_delay=100
    # t=0: attempt 1 fails, schedule at +100
    Process.sleep(20)
    Clock.advance(100)
    # t=100: attempt 2 fails, elapsed(100)+100=200 <= 350, schedule
    Process.sleep(20)
    Clock.advance(100)
    # t=200: attempt 3 fails, elapsed(200)+100=300 <= 350, schedule
    Process.sleep(20)
    Clock.advance(100)
    # t=300: attempt 4 fails, elapsed(300)+100=400 > 350, exhausted
    Process.sleep(20)

    assert {:error, :budget_exhausted, _reason, 4} = Task.await(task, 5_000)

    Agent.stop(agent)
  end