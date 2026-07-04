  test "max_delay_ms caps the computed delay", %{rw: _rw} do
    start_supervised!({Counter, 0})
    test_pid = self()

    # Use a random that always returns the max (prev_delay * 3)
    # to exercise the cap
    max_random = fn _min, max -> max end

    {:ok, rw2} =
      BudgetRetryWorker.start_link(
        clock: &Clock.now/0,
        random: max_random
      )

    func = fn ->
      attempt = Counter.increment_and_get()
      send(test_pid, {:attempt, attempt, Clock.now()})

      if attempt <= 3, do: {:error, :fail}, else: {:ok, :done}
    end

    task =
      Task.async(fn ->
        BudgetRetryWorker.execute(rw2, func,
          budget_ms: 100_000,
          base_delay_ms: 100,
          max_delay_ms: 500
        )
      end)

    # Attempt 1 at t=0. prev=100, next=random(100,300)=300, capped=min(300,500)=300
    assert_receive {:attempt, 1, _}
    Clock.advance(300)

    # Attempt 2 at t=300. prev=300, next=random(100,900)=900, capped=min(900,500)=500
    assert_receive {:attempt, 2, _}
    Clock.advance(500)

    # Attempt 3 at t=800. prev=500, next=random(100,1500)=1500, capped=min(1500,500)=500
    assert_receive {:attempt, 3, _}
    Clock.advance(500)

    assert_receive {:attempt, 4, _}

    assert {:ok, :done} = Task.await(task, 5_000)
  end