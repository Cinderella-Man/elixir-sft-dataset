  test "an element that times out once but succeeds on retry returns {:ok, value}" do
    {:ok, agent} = Agent.start_link(fn -> %{} end)

    func = fn x ->
      n =
        Agent.get_and_update(agent, fn m ->
          c = Map.get(m, x, 0) + 1
          {c, Map.put(m, x, c)}
        end)

      if n == 1, do: Process.sleep(300)
      x * 2
    end

    results = RetryMap.pmap([1, 2, 3], func, max_concurrency: 3, timeout: 100, max_attempts: 3)
    assert results == [{:ok, 2}, {:ok, 4}, {:ok, 6}]
  end