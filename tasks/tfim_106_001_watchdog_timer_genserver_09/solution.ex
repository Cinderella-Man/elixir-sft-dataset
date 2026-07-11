  test "timeout fires exactly once then stops" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, :worker}, 1_000
    # Must not fire again for the same (now removed) registration.
    refute_receive {:timed_out, :worker}, 300
  end