  test "registrations are independent" do
    test = self()
    :ok = GraceWatchdog.register(:fast, dummy_pid(), 40, 2, notifier(test))
    :ok = GraceWatchdog.register(:slow, dummy_pid(), 10_000, 2, notifier(test))

    assert_receive {:timed_out, :fast, 2}, 1_000
    refute_receive {:timed_out, :slow, _}, 100
  end