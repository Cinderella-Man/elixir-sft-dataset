  test "dead process with duplicate subscriptions on one topic is fully cleaned", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, _} = EventBus.subscribe(bus, "t", child)
    {:ok, _} = EventBus.subscribe(bus, "t", child)

    send(child, :stop)
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # Synchronous no-op publish; once it returns, the :DOWN has been handled.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    {:ok, _} = EventBus.subscribe(bus, "t", self())
    EventBus.publish(bus, "t", :check)

    # Only our single subscription should deliver; the two dead ones are gone.
    assert_receive {:event, "t", :check}, 500
    refute_receive {:event, "t", :check}, 200
  end