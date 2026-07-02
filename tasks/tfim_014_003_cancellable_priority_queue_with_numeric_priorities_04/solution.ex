  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    CancellablePriorityQueue.enqueue(pq, "first", 5)
    CancellablePriorityQueue.enqueue(pq, "second", 5)
    CancellablePriorityQueue.enqueue(pq, "third", 5)

    CancellablePriorityQueue.drain(pq)

    tasks = CancellablePriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end