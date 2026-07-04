  test "processed returns empty list when nothing has been processed", %{pq: pq} do
    assert PriorityQueue.processed(pq) == []
  end