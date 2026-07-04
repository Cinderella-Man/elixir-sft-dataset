  test "lower priority numbers are processed first", %{pq: _pq} do
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

    # Occupy the processor
    CancellablePriorityQueue.enqueue(pq2, "blocker", 99)
    Process.sleep(10)

    # Enqueue in reverse priority order
    CancellablePriorityQueue.enqueue(pq2, "pri_10", 10)
    CancellablePriorityQueue.enqueue(pq2, "pri_5", 5)
    CancellablePriorityQueue.enqueue(pq2, "pri_0", 0)
    CancellablePriorityQueue.enqueue(pq2, "pri_1", 1)
    CancellablePriorityQueue.enqueue(pq2, "pri_5b", 5)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == ["blocker", "pri_0", "pri_1", "pri_5", "pri_5b", "pri_10"]
  end