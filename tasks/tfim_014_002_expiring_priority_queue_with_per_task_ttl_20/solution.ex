  test "default_ttl_ms defaults to 5000 when the option is omitted" do
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
        clock: clock_fn(clock_agent)
      )

    ExpiringPriorityQueue.enqueue(pq, "blocker", :normal, ttl_ms: 100_000)
    assert_receive :blocker_started, 2000

    ExpiringPriorityQueue.enqueue(pq, "uses_default", :normal)

    advance_clock(clock_agent, 4999)
    assert ExpiringPriorityQueue.status(pq).normal == 1

    advance_clock(clock_agent, 2)
    assert ExpiringPriorityQueue.status(pq).normal == 0

    Process.exit(gate, :kill)
    ExpiringPriorityQueue.drain(pq)

    assert ExpiringPriorityQueue.expired(pq) == [{"uses_default", :normal}]
    assert Enum.map(ExpiringPriorityQueue.processed(pq), &elem(&1, 0)) == ["blocker"]
  end