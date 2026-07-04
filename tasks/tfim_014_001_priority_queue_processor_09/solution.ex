  test "status on empty queue returns all zeros", %{pq: pq} do
    assert PriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0}
  end