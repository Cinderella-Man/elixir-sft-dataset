  test "the :name option registers the server so the API can be driven by name" do
    clock_agent = start_clock(0)
    name = :expiring_priority_queue_named_server

    {:ok, pid} =
      ExpiringPriorityQueue.start_link(
        name: name,
        processor: fn task -> {:ok, task} end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 10_000
      )

    assert Process.whereis(name) == pid

    assert :ok = ExpiringPriorityQueue.enqueue(name, "named", :normal)
    assert :ok = ExpiringPriorityQueue.drain(name)

    assert ExpiringPriorityQueue.processed(name) == [{"named", {:ok, "named"}}]
    assert ExpiringPriorityQueue.expired(name) == []
    assert ExpiringPriorityQueue.status(name) == %{high: 0, normal: 0, low: 0, expired: 0}
  end