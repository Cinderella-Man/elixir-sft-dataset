  test "returns the last error reason on exhaustion", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :"fail_#{n}"}
    end

    assert {:error, :max_retries_exceeded, last_reason} =
             TimeoutRetryWorker.execute(rw, func,
               max_retries: 2,
               base_delay_ms: 50,
               attempt_timeout_ms: 5_000
             )

    assert last_reason == :fail_3

    Agent.stop(agent)
  end