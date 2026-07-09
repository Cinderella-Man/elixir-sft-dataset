  test "an exception is permanent and is NOT retried" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Agent.update(agent, &(&1 + 1))
          raise "boom"
        end,
        max_concurrency: 1,
        timeout: 1000,
        max_attempts: 3
      )

    assert match?([{:error, {:exception, _}}], results)
    assert Agent.get(agent, & &1) == 1
  end