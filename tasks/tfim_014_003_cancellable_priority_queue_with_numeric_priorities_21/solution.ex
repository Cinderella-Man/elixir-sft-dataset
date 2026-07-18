  test "omitting the processor option defaults to the identity function" do
    {:ok, pq2} = CancellablePriorityQueue.start_link([])

    CancellablePriorityQueue.enqueue(pq2, "plain", 0)
    CancellablePriorityQueue.enqueue(pq2, 42, 1)
    assert :ok = CancellablePriorityQueue.drain(pq2)

    assert CancellablePriorityQueue.processed(pq2) == [{"plain", "plain"}, {42, 42}]
  end