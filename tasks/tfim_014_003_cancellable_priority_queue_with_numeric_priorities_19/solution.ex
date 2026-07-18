  test "handles many concurrent enqueues without losing tasks", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(1)
          {:done, task}
        end
      )

    tasks =
      for i <- 1..50 do
        priority = rem(i, 10)
        {i, priority}
      end

    tasks
    |> Enum.map(fn {i, pri} ->
      Task.async(fn -> CancellablePriorityQueue.enqueue(pq2, i, pri) end)
    end)
    |> Enum.each(&Task.await/1)

    CancellablePriorityQueue.drain(pq2)

    processed = CancellablePriorityQueue.processed(pq2)
    assert length(processed) == 50

    processed_tasks = Enum.map(processed, &elem(&1, 0)) |> Enum.sort()
    assert processed_tasks == Enum.to_list(1..50)
  end