  test "status shows expired count after processing" do
    clock_agent = start_clock(0)
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          ref = Process.monitor(gate)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 50
      )

    # Occupy processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    status = ExpiringPriorityQueue.status(pq)
    assert status.expired == 2
  end