  test "processes multiple tasks of the same priority in FIFO order" do
    clock_agent = start_clock(0)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: recording_processor(),
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    ExpiringPriorityQueue.enqueue(pq, "first", :normal)
    ExpiringPriorityQueue.enqueue(pq, "second", :normal)
    ExpiringPriorityQueue.enqueue(pq, "third", :normal)

    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["first", "second", "third"]
  end