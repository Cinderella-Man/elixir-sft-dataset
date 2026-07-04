  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = ConcurrentPriorityQueue.drain(pq)
  end