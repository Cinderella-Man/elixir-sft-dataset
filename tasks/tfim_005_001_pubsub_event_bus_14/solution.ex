  test "dead subscriber is automatically cleaned up", %{bus: bus} do
    child =
      spawn(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, _ref} = EventBus.subscribe(bus, "t", child)

    # Kill the subscriber
    send(child, :stop)
    # Wait for the process to actually be dead
    ref = Process.monitor(child)
    assert_receive {:DOWN, ^ref, :process, ^child, _}, 500

    # A publish to a topic nobody subscribed to is a synchronous no-op; once it
    # returns, the bus has already handled the subscriber's :DOWN message.
    assert :ok = EventBus.publish(bus, "barrier", :sync)

    # Now publish — nobody should receive it, and it shouldn't crash
    assert :ok = EventBus.publish(bus, "t", :ghost)

    refute_receive {:event, "t", :ghost}, 200
  end