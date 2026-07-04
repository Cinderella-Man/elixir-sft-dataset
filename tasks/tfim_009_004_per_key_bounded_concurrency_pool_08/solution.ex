  test "limits concurrent executions to max_concurrency" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 2)
    {:ok, peak} = Agent.start_link(fn -> 0 end)
    {:ok, current} = Agent.start_link(fn -> 0 end)

    tasks =
      for _ <- 1..6 do
        Task.async(fn ->
          KeyedPool.execute(kp, :limited, fn ->
            Agent.update(current, &(&1 + 1))
            cur = Agent.get(current, & &1)
            Agent.update(peak, fn p -> max(p, cur) end)
            Process.sleep(100)
            Agent.update(current, &(&1 - 1))
            {:ok, :done}
          end)
        end)
      end

    Task.await_many(tasks, 10_000)

    # Peak concurrency should never exceed 2
    assert Agent.get(peak, & &1) <= 2
  end