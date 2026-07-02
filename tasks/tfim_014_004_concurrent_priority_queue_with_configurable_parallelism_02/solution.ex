  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ConcurrentPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ConcurrentPriorityQueue.processed(pq)
  end