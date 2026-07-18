  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = Enum.at([:high, :normal, :low], rem(i, 3))
        {i, priority}
      end

    # Enqueue from multiple processes concurrently
    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> PriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    PriorityQueue.drain(pq2)

    processed = PriorityQueue.processed(pq2)
    assert length(processed) == 50

    # Verify all tasks were processed (order may vary due to concurrent enqueue)
    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end