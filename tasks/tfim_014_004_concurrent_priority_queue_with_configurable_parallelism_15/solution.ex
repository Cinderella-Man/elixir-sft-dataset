  test "drain blocks until active workers finish, not just until queue is empty" do
    {:ok, pq} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          Process.sleep(100)
          {:processed, task}
        end,
        max_concurrency: 3
      )

    ConcurrentPriorityQueue.enqueue(pq, "a", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "b", :normal)
    ConcurrentPriorityQueue.enqueue(pq, "c", :normal)

    # Queue is drained quickly (all 3 start immediately), but workers take 100ms
    ConcurrentPriorityQueue.drain(pq)

    # If drain returned, all workers must be finished
    processed = ConcurrentPriorityQueue.processed(pq)
    assert length(processed) == 3
    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 0
  end