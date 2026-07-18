  test "handles many concurrent enqueues without losing non-expired tasks" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 1_000_000
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ExpiringPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end