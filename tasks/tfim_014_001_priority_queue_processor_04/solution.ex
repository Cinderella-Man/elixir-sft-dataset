  test "high priority tasks are processed before normal and low", %{pq: pq} do
    # Enqueue a low-priority task first so the processor picks it up
    # and is busy while we enqueue the rest.
    PriorityQueue.enqueue(pq, "low_1", :low)

    # Give processor a moment to start on low_1
    Process.sleep(2)

    # Now enqueue mixed priorities while processor is busy
    PriorityQueue.enqueue(pq, "low_2", :low)
    PriorityQueue.enqueue(pq, "normal_1", :normal)
    PriorityQueue.enqueue(pq, "high_1", :high)
    PriorityQueue.enqueue(pq, "normal_2", :normal)
    PriorityQueue.enqueue(pq, "high_2", :high)

    PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # low_1 was already being processed, so it comes first.
    # After that: high_1, high_2 (high FIFO), normal_1, normal_2 (normal FIFO), low_2
    assert tasks == ["low_1", "high_1", "high_2", "normal_1", "normal_2", "low_2"]
  end