  test "status on empty queue returns all zeros", %{pq: pq} do
    status = CancellablePriorityQueue.status(pq)
    assert status == %{pending: 0, by_priority: %{}, cancelled: 0}
  end