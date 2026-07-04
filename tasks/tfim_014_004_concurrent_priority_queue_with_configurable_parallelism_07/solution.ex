  test "concurrency=1 behaves like a sequential queue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(10)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 1
      )

    for i <- 1..5 do
      ConcurrentPriorityQueue.enqueue(pq, i, :normal)
    end

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark == 1

    Agent.stop(hwm_agent)
  end