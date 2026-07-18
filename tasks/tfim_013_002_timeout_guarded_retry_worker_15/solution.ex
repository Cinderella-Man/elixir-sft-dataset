  test "default base_delay_ms of 100 doubles for each successive retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [100, 200, 400]
    Agent.stop(agent)
  end