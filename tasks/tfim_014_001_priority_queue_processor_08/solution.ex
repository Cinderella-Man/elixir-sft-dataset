  test "drain on empty queue returns immediately", %{pq: pq} do
    assert :ok = PriorityQueue.drain(pq)
  end