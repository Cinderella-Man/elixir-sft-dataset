  test "remaining subscription is still cleaned up after a sibling unsubscribe", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, ref1} = EventBus.subscribe(bus, "t", child)
    {:ok, _ref2} = EventBus.subscribe(bus, "t", child)

    :ok = EventBus.unsubscribe(bus, "t", ref1)

    send(child, :stop)
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # Synchronous no-op publish; once it returns, the :DOWN has been handled.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    {:ok, _} = EventBus.subscribe(bus, "t", self())
    EventBus.publish(bus, "t", :after_down)

    assert_receive {:event, "t", :after_down}, 500
    refute_receive {:event, "t", :after_down}, 200
  end