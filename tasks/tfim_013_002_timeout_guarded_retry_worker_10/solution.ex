  test "multiple concurrent executions don't block each other", %{rw: rw} do
    # func1 succeeds immediately
    func1 = fn -> {:ok, :fast} end

    # func2 fails once then succeeds
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func2 = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n <= 1, do: {:error, :not_yet}, else: {:ok, :slow}
    end

    task1 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func1,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    task2 =
      Task.async(fn ->
        TimeoutRetryWorker.execute(rw, func2,
          max_retries: 3,
          base_delay_ms: 100,
          attempt_timeout_ms: 5_000
        )
      end)

    # func1 should return immediately
    assert {:ok, :fast} = Task.await(task1, 2_000)

    # func2 retries and eventually succeeds
    assert {:ok, :slow} = Task.await(task2, 5_000)
    Agent.stop(agent)
  end