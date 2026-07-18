  test "processed records a {task, result} pair when the processor returns nil" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn _task -> nil end,
        max_concurrency: 1
      )

    assert :ok = ConcurrentPriorityQueue.enqueue(pq, "nil_task", :normal)
    assert :ok = ConcurrentPriorityQueue.drain(pq)

    assert ConcurrentPriorityQueue.processed(pq) == [{"nil_task", nil}]
  end