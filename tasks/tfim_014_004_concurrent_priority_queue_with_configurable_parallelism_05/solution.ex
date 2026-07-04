  test "processes multiple tasks concurrently up to max_concurrency" do
    # Use an Agent to track the high-water mark of concurrent workers
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          # Increment active count
          Agent.update(hwm_agent, fn {current, max} ->
            new = current + 1
            {new, max(max, new)}
          end)

          Process.sleep(50)

          # Decrement active count
          Agent.update(hwm_agent, fn {current, max} -> {current - 1, max} end)

          {:processed, task}
        end,
        max_concurrency: 3
      )

    for i <- 1..9 do
      ConcurrentPriorityQueue.enqueue(pq, "task_#{i}", :normal)
    end

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)

    # The high-water mark should be exactly 3 (our max_concurrency)
    assert high_water_mark == 3

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 9

    Agent.stop(hwm_agent)
  end