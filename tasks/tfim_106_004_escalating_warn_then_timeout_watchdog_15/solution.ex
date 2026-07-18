  test "heartbeat after the warning defers the timeout past its original deadline" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.heartbeat(:w)

    # The original timeout deadline (~200ms from registration) must pass silently.
    refute_receive {:timed_out, :w}, 180
    assert :ok = EscalatingWatchdog.unregister(:w)
  end