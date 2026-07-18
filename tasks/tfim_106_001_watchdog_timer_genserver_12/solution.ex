  test "unregistering one name does not affect another" do
    test = self()
    :ok = Watchdog.register(:keep, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:drop, dummy_pid(), 60, notifier(test))

    assert :ok = Watchdog.unregister(:drop)

    assert_receive {:timed_out, :keep}, 1_000
    refute_receive {:timed_out, :drop}, 100
  end