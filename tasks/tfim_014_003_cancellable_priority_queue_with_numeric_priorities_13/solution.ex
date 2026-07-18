  test "peek returns the next task without removing it", %{pq: _pq} do
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

    CancellablePriorityQueue.enqueue(pq2, "low", 10)
    CancellablePriorityQueue.enqueue(pq2, "high", 1)

    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)
    # Peek again — still there
    assert {:ok, "high", 1} = CancellablePriorityQueue.peek(pq2)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end