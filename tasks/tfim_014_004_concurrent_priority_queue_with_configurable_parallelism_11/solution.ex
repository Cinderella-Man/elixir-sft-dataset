  test "status on empty queue returns all zeros", %{pq: pq} do
    status = ConcurrentPriorityQueue.status(pq)
    assert status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 1}
  end