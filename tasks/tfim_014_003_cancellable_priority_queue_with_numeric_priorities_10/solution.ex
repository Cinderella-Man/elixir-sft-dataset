  test "double cancel returns error on second attempt", %{pq: _pq} do
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

    {:ok, ref} = CancellablePriorityQueue.enqueue(pq2, "target", 1)

    assert :ok = CancellablePriorityQueue.cancel(pq2, ref)
    assert {:error, :not_found} = CancellablePriorityQueue.cancel(pq2, ref)

    Process.exit(gate, :kill)
    CancellablePriorityQueue.drain(pq2)
  end