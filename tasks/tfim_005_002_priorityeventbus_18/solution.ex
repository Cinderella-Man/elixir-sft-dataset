  test "start_link registers the bus under :name and serves the whole API by name" do
    name = :"priority_event_bus_#{System.pid()}_#{System.unique_integer([:positive])}"
    {:ok, pid} = PriorityEventBus.start_link(name: name, delivery_timeout_ms: 200)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.whereis(name) == pid

    sub = spawn_sub(:named, policy: :ack)
    {:ok, ref} = PriorityEventBus.subscribe(name, "t", sub, 7)
    assert [{^ref, ^sub, 7}] = PriorityEventBus.subscribers(name, "t")

    assert {:ok, 1} = PriorityEventBus.publish(name, "t", :evt)
    assert_receive {:got, :named, "t", :evt}

    assert :ok = PriorityEventBus.unsubscribe(name, "t", ref)
    assert [] = PriorityEventBus.subscribers(name, "t")
  end