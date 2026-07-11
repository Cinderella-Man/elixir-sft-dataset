  test "registrations are independent" do
    test = self()
    :ok = Watchdog.register(:fast, dummy_pid(), 60, notifier(test))
    :ok = Watchdog.register(:slow, dummy_pid(), 10_000, notifier(test))

    assert_receive {:timed_out, :fast}, 1_000
    # The slow one must not have fired.
    refute_receive {:timed_out, :slow}, 100
  end