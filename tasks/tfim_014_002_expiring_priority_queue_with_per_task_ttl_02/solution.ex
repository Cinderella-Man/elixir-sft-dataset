  test "processes a single enqueued task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert :ok = ExpiringPriorityQueue.enqueue(pq, "task_a", :normal)
    assert :ok = ExpiringPriorityQueue.drain(pq)

    assert [{"task_a", {:processed, "task_a"}}] = ExpiringPriorityQueue.processed(pq)
    assert [] = ExpiringPriorityQueue.expired(pq)
  end