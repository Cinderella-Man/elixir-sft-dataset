  test "handles many concurrent enqueues with high concurrency" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end,
        max_concurrency: 10
      )

    tasks =
      for i <- 1..100 do
        priority = Enum.at([:critical, :normal, :low], rem(i, 3))
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> ConcurrentPriorityQueue.enqueue(pq, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    ConcurrentPriorityQueue.drain(pq)

    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 100

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..100)
  end