  test "a task whose expiry equals the current clock is expired, not pending" do
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

    # Occupy the processor so "boundary" stays queued while we move the clock.
    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    # Enqueued at clock 0 with a 1000ms TTL -> expires_at == 1000.
    ExpiringPriorityQueue.enqueue(pq, "boundary", :high, ttl_ms: 1000)

    # One tick before the deadline the task is still pending.
    advance_clock(clock_agent, 999)
    assert ExpiringPriorityQueue.status(pq).high == 1

    # Exactly at the deadline the TTL window is over: the task is no longer pending.
    advance_clock(clock_agent, 1)
    assert ExpiringPriorityQueue.status(pq).high == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    # ...and picking it up at exactly expires_at records it as expired, not processed.
    assert ExpiringPriorityQueue.expired(pq) == [{"boundary", :high}]
    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker"]
  end