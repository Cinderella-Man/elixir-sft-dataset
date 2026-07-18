  test "default max_retries of 3 allows exactly four invocations" do
    worker = start_supervised!({TimeoutRetryWorker, [random: fn _max -> 0 end]})
    {:ok, calls} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(calls, &(&1 + 1))
      {:error, :boom}
    end

    assert {:error, :max_retries_exceeded, :boom} =
             TimeoutRetryWorker.execute(worker, func,
               base_delay_ms: 1,
               max_delay_ms: 1,
               attempt_timeout_ms: 1_000
             )

    assert Agent.get(calls, & &1) == 4
    Agent.stop(calls)
  end