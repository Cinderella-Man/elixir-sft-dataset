  test "jitter function is called with the capped delay on every positive-delay retry" do
    {agent, random} = recording_random()
    worker = start_supervised!({TimeoutRetryWorker, [random: random]})

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, always_fails(),
               max_retries: 3,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert recorded_delays(agent) == [1, 1, 1]
    Agent.stop(agent)
  end