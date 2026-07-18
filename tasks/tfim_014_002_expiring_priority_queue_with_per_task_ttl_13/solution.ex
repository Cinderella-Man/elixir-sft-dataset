  test "queue returns to idle after a task finishes so later enqueues still run" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    assert :ok = ExpiringPriorityQueue.enqueue(pq, "one", :normal)
    assert await_drain(pq) == {:ok, :ok}
    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["one"]

    # The processor is idle again, so a fresh enqueue must trigger processing.
    assert :ok = ExpiringPriorityQueue.enqueue(pq, "two", :high)
    assert await_drain(pq) == {:ok, :ok}

    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["one", "two"]
    assert ExpiringPriorityQueue.expired(pq) == []
    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
  end