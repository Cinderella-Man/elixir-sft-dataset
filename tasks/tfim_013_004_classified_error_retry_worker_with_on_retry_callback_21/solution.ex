  test "injected random is called with the pre-jitter capped delay as argument" do
    test_pid = self()

    {:ok, rw2} =
      ClassifiedRetryWorker.start_link(
        random: fn max ->
          send(test_pid, {:rand_arg, max})
          0
        end
      )

    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      n = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)
      if n == 1, do: {:error, :transient, :x}, else: {:ok, :done}
    end

    assert {:ok, :done} =
             ClassifiedRetryWorker.execute(rw2, func, base_delay_ms: 100)

    assert_receive {:rand_arg, 100}
    Agent.stop(agent)
  end
