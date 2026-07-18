  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      CancellablePriorityQueue.start_link(processor: fn n -> n * 2 end)

    CancellablePriorityQueue.enqueue(pq2, 5, 1)
    CancellablePriorityQueue.enqueue(pq2, 10, 0)
    CancellablePriorityQueue.drain(pq2)

    result_map = Map.new(CancellablePriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end