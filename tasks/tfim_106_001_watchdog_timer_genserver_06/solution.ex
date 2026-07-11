  test "unregister prevents the callback from firing" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test))
    assert :ok = Watchdog.unregister(:worker)

    refute_receive {:timed_out, :worker}, 300
  end