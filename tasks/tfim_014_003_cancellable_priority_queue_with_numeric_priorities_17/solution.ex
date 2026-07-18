  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert CancellablePriorityQueue.processed(pq) == []
  end