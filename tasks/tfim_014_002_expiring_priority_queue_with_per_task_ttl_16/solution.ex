  test "status on empty queue returns all zeros" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        clock: clock_fn(clock_agent),
        default_ttl_ms: 5000
      )

    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
  end