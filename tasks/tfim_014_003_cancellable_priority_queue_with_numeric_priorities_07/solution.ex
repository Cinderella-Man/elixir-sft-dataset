  test "cancel removes a pending task", %{pq: _pq} do
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

    {:ok, ref_a} = CancellablePriorityQueue.enqueue(pq2, "will_cancel", 1)
    CancellablePriorityQueue.enqueue(pq2, "will_process", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref_a)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)

    tasks = CancellablePriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert "will_cancel" not in tasks
    assert "will_process" in tasks
  end