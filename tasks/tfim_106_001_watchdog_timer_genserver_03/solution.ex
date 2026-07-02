  test "fires the callback when a heartbeat is missed" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))

    # Never heartbeat -> timeout must fire.
    assert_receive {:timed_out, :worker}, 1_000
  end