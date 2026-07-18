  test "processor function receives and transforms the task" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn n -> n * 2 end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    ExpiringPriorityQueue.enqueue(pq, 5, :normal)
    ExpiringPriorityQueue.enqueue(pq, 10, :high)
    ExpiringPriorityQueue.drain(pq)

    result_map = Map.new(ExpiringPriorityQueue.processed(pq))
    assert result_map[5] == 10
    assert result_map[10] == 20
  end