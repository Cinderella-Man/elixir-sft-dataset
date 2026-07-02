  test "processes a single enqueued task", %{pq: pq} do
    assert :ok = PriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = PriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = PriorityQueue.processed(pq)
  end