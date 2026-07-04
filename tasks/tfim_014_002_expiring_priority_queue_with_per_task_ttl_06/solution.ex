  test "per-task TTL overrides default TTL" do
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
        default_ttl_ms: 1000
      )

    # Occupy the processor
    ExpiringPriorityQueue.enqueue(pq, "blocker", :high, ttl_ms: 100_000)
    Process.sleep(10)

    # Short custom TTL
    ExpiringPriorityQueue.enqueue(pq, "short_ttl", :normal, ttl_ms: 50)
    # Uses default TTL (1000ms)
    ExpiringPriorityQueue.enqueue(pq, "default_ttl", :normal)

    # Advance clock past short TTL but within default TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed_tasks = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired_tasks = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed_tasks == ["blocker", "default_ttl"]
    assert expired_tasks == ["short_ttl"]
  end