  test "multiple concurrent executions don't block each other", %{rw: rw} do
    func1 = fn -> {:ok, :fast} end

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

      if n <= 1,
        do: {:error, :transient, :not_yet},
        else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw, func1, max_retries: 3, base_delay_ms: 100)
      end)

    task2 =
      Task.async(fn ->
        ClassifiedRetryWorker.execute(rw, func2, max_retries: 3, base_delay_ms: 100)
      end)

    assert {:ok, :fast} = Task.await(task1, 2_000)

    Process.sleep(50)
    Clock.advance(200)

    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end