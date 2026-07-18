  test "zero delay never calls the jitter function yet still retries" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               max_retries: 3,
               base_delay_ms: 0,
               max_delay_ms: 100,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == []
    assert Agent.get(calls, & &1) == 4

    Agent.stop(calls)
    Agent.stop(agent)
  end