  test "with concurrency > 1, higher priority tasks still get slots first" do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
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

    # Fill both slots with blockers
    ConcurrentPriorityQueue.enqueue(pq, "blocker_1", :low)
    ConcurrentPriorityQueue.enqueue(pq, "blocker_2", :low)
    Process.sleep(10)

    # Queue up mixed priorities
    ConcurrentPriorityQueue.enqueue(pq, "low_a", :low)
    ConcurrentPriorityQueue.enqueue(pq, "critical_a", :critical)
    ConcurrentPriorityQueue.enqueue(pq, "normal_a", :normal)

    status = ConcurrentPriorityQueue.status(pq)
    assert status.active == 2
    assert status.critical == 1
    assert status.normal == 1
    assert status.low == 1

    # Release all blockers
    Process.exit(gate, :kill)
    ConcurrentPriorityQueue.drain(pq)

    tasks = ConcurrentPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    # Blockers finish first (in some order), then critical, normal, low
    # With concurrency=2, the two blockers finish ~simultaneously,
    # then critical_a and normal_a start together, then low_a
    blocker_tasks = Enum.take(tasks, 2) |> Enum.sort()
    assert blocker_tasks == ["blocker_1", "blocker_2"]

    remaining = Enum.drop(tasks, 2)
    # critical_a should appear before low_a in the remaining
    critical_idx = Enum.find_index(remaining, &(&1 == "critical_a"))
    low_idx = Enum.find_index(remaining, &(&1 == "low_a"))
    assert critical_idx < low_idx
  end