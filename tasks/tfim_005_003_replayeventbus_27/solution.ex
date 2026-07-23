  test "the :name option registers the bus and the whole API works through it" do
    name = :"replay_bus_#{System.pid()}_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      ReplayEventBus.start_link(
        name: name,
        clock: &Clock.now/0,
        default_history_size: 10,
        history_ttl_ms: 10_000,
        cleanup_interval_ms: :infinity
      )

    # The name must be a real process registration, not merely an init arg.
    assert Process.whereis(name) == pid

    # Every public function accepts the registered name as the server.
    assert :ok = ReplayEventBus.publish(name, "t", :a)
    {:ok, ref} = ReplayEventBus.subscribe(name, "t", self(), replay: :all)
    assert [:a] = drain("t")

    assert :ok = ReplayEventBus.publish(name, "t", :b)
    assert [:b] = drain("t")
    assert [:a, :b] = ReplayEventBus.history(name, "t")

    assert :ok = ReplayEventBus.set_history_size(name, "t", 1)
    assert [:b] = ReplayEventBus.history(name, "t")

    assert :ok = ReplayEventBus.unsubscribe(name, "t", ref)
    assert :ok = ReplayEventBus.publish(name, "t", :c)
    assert [] = drain("t")
  end