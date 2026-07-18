  test "enqueue refuses a priority outside high, normal and low" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert_raise FunctionClauseError, fn ->
      ExpiringPriorityQueue.enqueue(pq, "bad", :urgent)
    end

    assert_raise FunctionClauseError, fn ->
      ExpiringPriorityQueue.enqueue(pq, "bad", "high", ttl_ms: 100)
    end

    assert ExpiringPriorityQueue.status(pq) == %{high: 0, normal: 0, low: 0, expired: 0}
    assert ExpiringPriorityQueue.processed(pq) == []
  end