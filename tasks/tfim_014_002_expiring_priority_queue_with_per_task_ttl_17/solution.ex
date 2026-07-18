  test "processed and expired return empty lists when nothing has been enqueued" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.processed(pq) == []
    assert ExpiringPriorityQueue.expired(pq) == []
  end