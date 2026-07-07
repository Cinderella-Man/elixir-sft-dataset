  test "same-priority tasks run in FIFO order at concurrency=1", %{pq: pq} do
    ConcurrentPriorityQueue.enqueue(pq, "first", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "second", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "third", :normal)

    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end