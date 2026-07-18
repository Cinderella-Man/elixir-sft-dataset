  test "abnormal task exit is retryable so a later attempt can still succeed", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n == 1, do: exit(:kaboom), else: {:ok, :recovered}
    end

    assert {:ok, :recovered} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    Agent.stop(agent)
  end