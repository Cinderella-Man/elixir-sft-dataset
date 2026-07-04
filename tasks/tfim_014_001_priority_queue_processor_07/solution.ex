  test "FIFO is maintained within each priority level", %{pq: _pq} do
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq2} =
      PriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end
      )

    PriorityQueue.enqueue(pq2, "l_blocker", :low)
    Process.sleep(10)

    # Enqueue several tasks per level
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "n2", :normal)
    PriorityQueue.enqueue(pq2, "n3", :normal)
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))

    # Extract subsequences per priority
    high_tasks = Enum.filter(tasks, &String.starts_with?(&1, "h"))
    normal_tasks = Enum.filter(tasks, &String.starts_with?(&1, "n"))
    low_tasks = Enum.filter(tasks, &String.starts_with?(&1, "l"))

    assert high_tasks == ["h1", "h2"]
    assert normal_tasks == ["n1", "n2", "n3"]
    assert low_tasks == ["l_blocker", "l1", "l2"]
  end