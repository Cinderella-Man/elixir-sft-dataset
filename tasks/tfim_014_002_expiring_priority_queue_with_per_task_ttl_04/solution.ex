  test "high priority tasks are processed before normal and low" do
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
        default_ttl_ms: 100_000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low)
    Process.sleep(10)

    # Queue up tasks in reverse priority order
    ExpiringPriorityQueue.enqueue(pq, "low_a", :low)
    ExpiringPriorityQueue.enqueue(pq, "normal_a", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_a", :high)
    ExpiringPriorityQueue.enqueue(pq, "normal_b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "high_b", :high)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))

    assert tasks == [
             "blocker",
             "high_a",
             "high_b",
             "normal_a",
             "normal_b",
             "low_a"
           ]
  end