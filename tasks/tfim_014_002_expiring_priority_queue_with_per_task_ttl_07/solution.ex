  test "multiple expired tasks are skipped in sequence before finding a valid one" do
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
    ExpiringPriorityQueue.enqueue(pq, "blocker", :low, ttl_ms: 100_000)
    Process.sleep(10)

    # Enqueue several tasks with short TTL
    ExpiringPriorityQueue.enqueue(pq, "expire_1", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_2", :high)
    ExpiringPriorityQueue.enqueue(pq, "expire_3", :normal)
    # One with long TTL
    ExpiringPriorityQueue.enqueue(pq, "survivor", :low, ttl_ms: 100_000)

    # Advance past short TTL
    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    expired = ExpiringPriorityQueue.expired(pq) |> Enum.map(&elem(&1, 0))

    assert processed == ["blocker", "survivor"]
    assert expired == ["expire_1", "expire_2", "expire_3"]
  end