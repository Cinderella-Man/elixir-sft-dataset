  test "dead subscriber is removed from all topics; history preserved", %{bus: bus} do
    task =
      Task.async(fn ->
        {:ok, _r1} = ReplayEventBus.subscribe(bus, "a", self())
        {:ok, _r2} = ReplayEventBus.subscribe(bus, "b", self())
        :ready
      end)

    assert :ready = Task.await(task)

    # Wait for the subscriber process itself to be gone, then drive the bus
    # through the documented public API while it handles the :DOWN. The bus
    # is linked to this test process, so a bus whose :DOWN handling crashes
    # takes the test down with it; a healthy bus keeps serving publish/3 and
    # history/2. Internal state is deliberately not inspected.
    mref = Process.monitor(task.pid)
    assert_receive {:DOWN, ^mref, :process, _, _}, 1_000

    for _ <- 1..20 do
      assert :ok = ReplayEventBus.publish(bus, "down_sync", :ping)
      Process.sleep(5)
    end

    assert Process.alive?(bus)

    # Publishing to the dead subscriber's topics still works, and the
    # topic's history is preserved (history is per-topic, not per-subscriber).
    ReplayEventBus.publish(bus, "a", :survived)
    assert [:survived] = ReplayEventBus.history(bus, "a")
  end