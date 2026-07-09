  test "cancelled count is tracked in status", %{pq: _pq} do
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

    CancellablePriorityQueue.enqueue(pq2, "blocker", 0)
    Process.sleep(10)

    {:ok, ref1} = CancellablePriorityQueue.enqueue(pq2, "a", 1)
    {:ok, ref2} = CancellablePriorityQueue.enqueue(pq2, "b", 2)
    CancellablePriorityQueue.enqueue(pq2, "c", 3)

    CancellablePriorityQueue.cancel(pq2, ref1)
    CancellablePriorityQueue.cancel(pq2, ref2)

    status = CancellablePriorityQueue.status(pq2)
    assert status.cancelled == 2
    assert status.pending == 1

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end