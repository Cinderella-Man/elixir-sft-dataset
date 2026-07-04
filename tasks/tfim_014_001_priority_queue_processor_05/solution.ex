  test "high beats normal beats low in a clean queue", %{pq: _pq} do
    # Use a processor with a gate so nothing starts until we've enqueued everything
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          # Block until gate process is dead (will be killed below)
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    # Enqueue one task to occupy the processor at the gate
    PriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    PriorityQueue.enqueue(pq2, "low_a", :low)
    PriorityQueue.enqueue(pq2, "low_b", :low)
    PriorityQueue.enqueue(pq2, "normal_a", :normal)
    PriorityQueue.enqueue(pq2, "normal_b", :normal)
    PriorityQueue.enqueue(pq2, "high_a", :high)
    PriorityQueue.enqueue(pq2, "high_b", :high)

    # Release the gate — all queued tasks will now be processed in priority order
    Process.exit(gate, :kill)

    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # blocker was already running, then strict priority order
    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a",
             "low_b"
           ]
  end