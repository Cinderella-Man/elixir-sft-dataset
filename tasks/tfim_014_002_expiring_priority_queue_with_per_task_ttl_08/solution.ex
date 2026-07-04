  test "expired tasks record their original priority" do
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

    ExpiringPriorityQueue.enqueue(pq, "high_expired", :high)
    ExpiringPriorityQueue.enqueue(pq, "low_expired", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    expired = ExpiringPriorityQueue.expired(pq)
    assert {"high_expired", :high} in expired
    assert {"low_expired", :low} in expired
  end