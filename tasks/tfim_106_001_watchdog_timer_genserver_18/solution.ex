  test "a heartbeat after unregister does not revive the registration" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))
    assert :ok = Watchdog.unregister(:worker)

    # An unknown-name heartbeat must not re-arm anything for the retired registration.
    assert :ok = Watchdog.heartbeat(:worker)

    refute_receive {:timed_out, :worker}, 300
  end