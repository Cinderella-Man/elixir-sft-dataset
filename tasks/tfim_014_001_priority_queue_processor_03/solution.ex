  test "processes multiple tasks of the same priority in FIFO order", %{pq: pq} do
    PriorityQueue.enqueue(pq, "first", :normal)
    PriorityQueue.enqueue(pq, "second", :normal)
    PriorityQueue.enqueue(pq, "third", :normal)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end