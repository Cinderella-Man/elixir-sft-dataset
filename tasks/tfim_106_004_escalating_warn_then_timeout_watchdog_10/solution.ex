  test "unregister prevents both callbacks" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert :ok = EscalatingWatchdog.unregister(:w)

    refute_receive {:warned, :w}, 200
    refute_receive {:timed_out, :w}, 100
  end