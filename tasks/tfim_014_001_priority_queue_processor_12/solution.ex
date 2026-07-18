  test "becomes idle after draining and processes tasks enqueued later", %{pq: pq} do
    PriorityQueue.enqueue(pq, "batch1", :normal)
    assert :ok = PriorityQueue.drain(pq)
    assert [{"batch1", {:processed, "batch1"}}] = PriorityQueue.processed(pq)

    # Once the queue has fully drained the processor must be idle again, so a
    # brand new task enqueued now must trigger processing on its own. If the
    # server stayed "busy", this second drain would never return.
    PriorityQueue.enqueue(pq, "batch2", :high)
    assert :ok = PriorityQueue.drain(pq)

    tasks = PriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert tasks == ["batch1", "batch2"]
  end