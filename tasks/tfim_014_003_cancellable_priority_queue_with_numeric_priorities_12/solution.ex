  test "status reports pending counts by priority", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      CancellablePriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    CancellablePriorityQueue.enqueue(pq2, "a", 0)
    CancellablePriorityQueue.enqueue(pq2, "b", 0)
    CancellablePriorityQueue.enqueue(pq2, "c", 5)
    CancellablePriorityQueue.enqueue(pq2, "d", 10)
    CancellablePriorityQueue.enqueue(pq2, "e", 10)

    status = CancellablePriorityQueue.status(pq2)
    assert status.pending == 5
    assert status.by_priority == %{0 => 2, 5 => 1, 10 => 2}
    assert status.cancelled == 0

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    final_status = CancellablePriorityQueue.status(pq2)
    assert final_status.pending == 0
    assert final_status.by_priority == %{}
  end