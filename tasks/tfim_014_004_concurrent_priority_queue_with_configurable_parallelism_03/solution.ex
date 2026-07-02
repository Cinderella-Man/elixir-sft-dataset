  test "processes multiple tasks of the same priority in FIFO order with concurrency=1", %{pq: pq} do
    ConcurrentPriorityQueue.enqueue(pq, "first", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "second", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "third", :normal)

    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end