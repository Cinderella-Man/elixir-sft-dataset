  test "re-registering replaces the previous registration" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :old))
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :new))

    assert_receive {:new, :w}, 1_000
    refute_receive {:old, :w}, 100
  end