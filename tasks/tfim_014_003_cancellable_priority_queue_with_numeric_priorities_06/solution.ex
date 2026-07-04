  test "priority 0 is highest", %{pq: _pq} do
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

    CancellablePriorityQueue.enqueue(pq2, "low", 100)
    CancellablePriorityQueue.enqueue(pq2, "urgent", 0)
    CancellablePriorityQueue.enqueue(pq2, "medium", 50)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "urgent", "medium", "low"]
  end