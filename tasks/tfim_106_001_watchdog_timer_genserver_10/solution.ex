  test "heartbeat after a timeout is a no-op (registration already removed)" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000

    # The registration is gone; heartbeating must not re-arm anything.
    assert :ok = Watchdog.heartbeat(:worker)
    refute_receive {:timed_out, :worker}, 300
  end