  test "status reports pending counts excluding expired tasks" do
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

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue tasks — some will expire
    ExpiringPriorityQueue.enqueue(pq, "h1", :high, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "h2_short", :high, ttl_ms: 50)
    ExpiringPriorityQueue.enqueue(pq, "n1", :normal, ttl_ms: 100_000)
    ExpiringPriorityQueue.enqueue(pq, "l1_short", :low, ttl_ms: 50)

    # Advance clock to expire the short-TTL tasks
    advance_clock(clock_agent, 100)

    status = ExpiringPriorityQueue.status(pq)
    assert status.high == 1
    assert status.normal == 1
    assert status.low == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)
  end