  test "processes a single enqueued task", %{pq: pq} do
    assert {:ok, _ref} = CancellablePriorityQueue.enqueue(pq, "task_a", 1)
    assert :ok = CancellablePriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = CancellablePriorityQueue.processed(pq)
  end