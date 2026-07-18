  test "defaults max_concurrency to 1 when the option is omitted" do
    {:ok, pq} = ConcurrentPriorityQueue.start_link([])

    status = ConcurrentPriorityQueue.status(pq)
    assert status.max_concurrency == 1
    assert status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 1}
  end