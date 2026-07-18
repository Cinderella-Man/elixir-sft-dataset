  test "defaults the processor to the identity function when the option is omitted" do
    {:ok, pq} = ConcurrentPriorityQueue.start_link(max_concurrency: 1)

    assert :ok = ConcurrentPriorityQueue.enqueue(pq, "echo", :normal)
    assert :ok = ConcurrentPriorityQueue.drain(pq)

    assert ConcurrentPriorityQueue.processed(pq) == [{"echo", "echo"}]
  end