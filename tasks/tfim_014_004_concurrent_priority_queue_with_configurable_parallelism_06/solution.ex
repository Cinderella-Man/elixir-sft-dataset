  test "never exceeds max_concurrency even under burst enqueue" do
    {:ok, hwm_agent} = Agent.start_link(fn -> {0, 0} end)

    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Agent.update(hwm_agent, fn {c, m} -> {c + 1, max(m, c + 1)} end)
          Process.sleep(20)
          Agent.update(hwm_agent, fn {c, m} -> {c - 1, m} end)
          {:processed, task}
        end,
        max_concurrency: 5
      )

    # Burst enqueue 25 tasks from multiple processes
    1..25
    |> Enum.map(fn i ->
      Task.async(fn ->
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        ConcurrentPriorityQueue.enqueue(pq, i, priority)
      end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    {_current, high_water_mark} = Agent.get(hwm_agent, & &1)
    assert high_water_mark <= 5

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 25

    Agent.stop(hwm_agent)
  end