  test "processor function receives and transforms the task", %{pq: _pq} do
    {:ok, pq2} =
      PriorityQueue.start_link(processor: fn n -> n * 2 end)

    PriorityQueue.enqueue(pq2, 5, :normal)
    PriorityQueue.enqueue(pq2, 10, :high)
    PriorityQueue.drain(pq2)

    results = PriorityQueue.processed(pq2)

    # high comes first if it was queued before processing started,
    # but with fast processing, ordering may vary.
    # Just check both tasks were processed with correct results.
    assert {5, 10} in results or {10, 20} in results
    result_map = Map.new(results)
    assert result_map[5] == 10
    assert result_map[10] == 20
  end