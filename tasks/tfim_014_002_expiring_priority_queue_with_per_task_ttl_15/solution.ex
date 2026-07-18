  test "drain on empty queue returns immediately" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert :ok = ExpiringPriorityQueue.drain(pq)
  end