  test "all tasks expired results in empty processed list (except blocker)" do
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

    ExpiringPriorityQueue.enqueue(pq, "a", :high)
    ExpiringPriorityQueue.enqueue(pq, "b", :normal)
    ExpiringPriorityQueue.enqueue(pq, "c", :low)

    advance_clock(clock_agent, 100)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    processed = ExpiringPriorityQueue.processed(pq) |> Enum.map(&elem(&1, 0))
    assert processed == ["blocker"]
    assert length(ExpiringPriorityQueue.expired(pq)) == 3
  end