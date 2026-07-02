  test "fires repeatedly while heartbeats are missing" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
    assert_receive {:alert, :w}, 1_000
  end