  test "registers the server under the :name option and serves calls by that name" do
    name = :concurrent_priority_queue_named_audit

    {:ok, pid} =
      ConcurrentPriorityQueue.start_link(
        name: name,
        processor: fn task -> {:ok, task} end,
        max_concurrency: 1
      )

    assert Process.whereis(name) == pid
    assert :ok = ConcurrentPriorityQueue.enqueue(name, "named", :critical)
    assert :ok = ConcurrentPriorityQueue.drain(name)
    assert ConcurrentPriorityQueue.processed(name) == [{"named", {:ok, "named"}}]
  end