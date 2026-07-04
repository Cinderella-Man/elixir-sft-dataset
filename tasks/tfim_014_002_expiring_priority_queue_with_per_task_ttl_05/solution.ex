  test "expired tasks are skipped and recorded" do
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
        default_ttl_ms: 100
      )

    # Occupy the processor with a blocker that has a long TTL
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue a task with default short TTL — it stays queued
    ExpiringPriorityQueue.enqueue(pq, "will_expire", :normal)

    # Enqueue a task with long TTL
    ExpiringPriorityQueue.enqueue(pq, "still_valid", :normal, ttl_ms: 50_000)

    # Advance clock past default TTL
    advance_clock(clock_agent, 200)

    # Release the gate — blocker finishes, then process_next finds will_expire is expired
    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq)

    assert processed == ["blocker", "still_valid"]
    assert [{"will_expire", :normal}] = expired
  end