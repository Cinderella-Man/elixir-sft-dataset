  test "peek on empty queue returns :empty", %{pq: pq} do
    assert :empty = CancellablePriorityQueue.peek(pq)
  end