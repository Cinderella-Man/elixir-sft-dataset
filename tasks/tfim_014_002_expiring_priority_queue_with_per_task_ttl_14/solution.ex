  test "queue returns to idle after a round where every candidate task expired" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    # A zero TTL expires the moment :process_next looks at it, so this round of
    # processing finds nothing to run and must leave the processor idle.
    assert :ok = ExpiringPriorityQueue.enqueue(pq, "dead", :normal, ttl_ms: 0)
    assert ExpiringPriorityQueue.expired(pq) == [{"dead", :normal}]
    assert ExpiringPriorityQueue.processed(pq) == []

    # Idle again: this task must be picked up.
    assert :ok = ExpiringPriorityQueue.enqueue(pq, "alive", :normal, ttl_ms: 100_000)
    assert await_drain(pq) == {:ok, :ok}

    assert ExpiringPriorityQueue.processed(pq) == [{"alive", {:processed, "alive"}}]
    assert ExpiringPriorityQueue.expired(pq) == [{"dead", :normal}]
    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 1}
  end