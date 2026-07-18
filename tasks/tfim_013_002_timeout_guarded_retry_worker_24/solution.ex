  test "re-running execute on the same server restarts attempt counting from zero", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(agent, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.update(agent, fn _ -> 0 end)

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 0,
               max_delay_ms: 0,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(agent, & &1) == 3

    Agent.stop(agent)
  end