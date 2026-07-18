  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        max_concurrency: 1
      )

    ConcurrentPriorityQueue.enqueue(pq2, 5, :normal)
    ConcurrentPriorityQueue.enqueue(pq2, 10, :critical)
    ConcurrentPriorityQueue.drain(pq2)

    result_map = Map.new(ConcurrentPriorityQueue.processed(pq2))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end