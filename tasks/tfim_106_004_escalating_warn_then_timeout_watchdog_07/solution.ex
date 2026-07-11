  test "heartbeat after warn re-arms so the warning can fire again and the timeout is deferred" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        50,
        250,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)

    # The warning re-arms and fires again from the fresh clock...
    assert_receive {:warned, :w}, 1_000
    # ...and the timeout has not fired because the clock was reset.
    refute_receive {:timed_out, :w}, 10

    assert :ok = EscalatingWatchdog.unregister(:w)
  end