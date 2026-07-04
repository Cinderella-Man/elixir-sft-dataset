  test "enqueue with all three priorities in reverse order", %{pq: _pq} do
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

    PriorityQueue.enqueue(pq2, "blocker", :high)
    Process.sleep(10)

    PriorityQueue.enqueue(pq2, "low_only", :low)
    PriorityQueue.enqueue(pq2, "normal_only", :normal)
    PriorityQueue.enqueue(pq2, "high_only", :high)

    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    tasks = PriorityQueue.processed(pq2) |> Enum.map(&elem(&1, 0))
    assert tasks == ["blocker", "high_only", "normal_only", "low_only"]
  end