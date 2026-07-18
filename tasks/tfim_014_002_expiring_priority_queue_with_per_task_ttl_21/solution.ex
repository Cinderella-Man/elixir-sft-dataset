  test "identical ttl_ms values expire relative to each task's own enqueue time" do
    clock_agent = start_clock(0)
    parent = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    {:ok, pq} =
      ExpiringPriorityQueue.start_link(
        processor: fn task ->
          if task == "blocker" do
            send(parent, :blocker_started)
            ref = Process.monitor(gate)

            receive do
              {:DOWN, ^ref, _, _, _} -> :ok
            end
          end

          {:processed, task}
        end,
        clock: clock_fn(clock_agent),
        default_ttl_ms: 100_000
      )

    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    # Enqueued at clock 0 -> expires at 1000
    ExpiringPriorityQueue.enqueue(pq, "early", :normal, ttl_ms: 1000)

    advance_clock(clock_agent, 800)

    # Same ttl_ms, but enqueued at clock 800 -> expires at 1800
    ExpiringPriorityQueue.enqueue(pq, "late", :normal, ttl_ms: 1000)

    advance_clock(clock_agent, 400)

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker", "late"]
    assert ExpiringPriorityQueue.expired(pq) == [{"early", :normal}]
  end