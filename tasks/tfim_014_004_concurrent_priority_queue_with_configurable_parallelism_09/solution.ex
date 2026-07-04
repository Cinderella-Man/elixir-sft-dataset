  test "status reports accurate counts", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      ConcurrentPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        max_concurrency: 2
      )

    # Fill both slots
    ConcurrentPriorityQueue.enqueue(pq2, "active_1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "active_2", :normal)
    Process.sleep(10)

    # Queue pending tasks
    ConcurrentPriorityQueue.enqueue(pq2, "c1", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "n1", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "l1", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "l2", :low)

    status = ConcurrentPriorityQueue.status(pq2)
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 2
    assert status.active == 2
    assert status.max_concurrency == 2

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    final_status = ConcurrentPriorityQueue.status(pq2)
    assert final_status == %{critical: 0, normal: 0, low: 0, active: 0, max_concurrency: 2}
  end