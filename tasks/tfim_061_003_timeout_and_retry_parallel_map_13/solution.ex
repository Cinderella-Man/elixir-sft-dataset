  test "max_attempts defaults to 1 so a timed-out element is attempted exactly once" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    results =
      RetryMap.pmap(
        [1],
        fn _ ->
          Agent.update(agent, &(&1 + 1))
          Process.sleep(300)
          :never
        end,
        max_concurrency: 1,
        timeout: 60
      )

    assert results == [{:error, :timeout}]
    assert Agent.get(agent, & &1) == 1
  end