  test "registrations are independent" do
    test = self()
    :ok = RecurringWatchdog.register(:fast, dummy_pid(), 50, notifier(test))
    :ok = RecurringWatchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:alert, :fast}, 1_000
    refute_receive {:alert, :slow}, 100
  end