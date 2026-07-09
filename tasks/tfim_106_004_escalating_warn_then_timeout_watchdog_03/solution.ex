  test "warn fires first, then timeout" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        60,
        150,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert_receive {:timed_out, :w}, 1_000
  end