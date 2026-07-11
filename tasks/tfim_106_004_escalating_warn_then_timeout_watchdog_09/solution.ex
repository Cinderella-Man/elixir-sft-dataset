  test "registrations are independent" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :fast,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    :ok =
      EscalatingWatchdog.register(
        :slow,
        dummy_pid(),
        5_000,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:timed_out, :fast}, 1_000
    refute_receive {:warned, :slow}, 50
  end