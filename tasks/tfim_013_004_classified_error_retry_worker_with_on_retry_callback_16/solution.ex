  test "returns the last transient error reason on exhaustion", %{rw: rw} do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      {:error, :transient, :"fail_#{n}"}
    end

    assert {:error, :retries_exhausted, last_reason} =
             ClassifiedRetryWorker.execute(rw, func, max_retries: 2, base_delay_ms: 50)

    assert last_reason == :fail_3

    Agent.stop(agent)
  end