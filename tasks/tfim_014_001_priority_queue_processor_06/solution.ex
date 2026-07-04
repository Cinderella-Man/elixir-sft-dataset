  test "status reports pending counts accurately", %{pq: _pq} do
    # Use a gated processor so tasks pile up
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

    # Enqueue one to occupy the processor
    PriorityQueue.enqueue(pq2, "blocker", :normal)
    Process.sleep(10)

    # These will all be pending
    PriorityQueue.enqueue(pq2, "h1", :high)
    PriorityQueue.enqueue(pq2, "h2", :high)
    PriorityQueue.enqueue(pq2, "n1", :normal)
    PriorityQueue.enqueue(pq2, "l1", :low)
    PriorityQueue.enqueue(pq2, "l2", :low)
    PriorityQueue.enqueue(pq2, "l3", :low)

    status = PriorityQueue.status(pq2)
    assert status.high == 2
    assert status.normal == 1
    assert status.low == 3

    # Release and let everything finish
    Process.exit(gate, :kill)
    PriorityQueue.drain(pq2)

    status_after = PriorityQueue.status(pq2)
    assert status_after == %{high: 0, normal: 0, low: 0}
  end