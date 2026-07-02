  test "critical > normal > low priority ordering", %{pq: _pq} do
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
        max_concurrency: 1
      )

    # Occupy the single slot
    ConcurrentPriorityQueue.enqueue(pq2, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ConcurrentPriorityQueue.enqueue(pq2, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_a", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq2, "normal_b", :normal)
    ConcurrentPriorityQueue.enqueue(pq2, "critical_b", :critical)

    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq2)

    tasks = ConcurrentPriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "critical_a",
             "critical_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end