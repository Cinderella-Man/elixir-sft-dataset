  test "heartbeat before warn prevents the warning in that window" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        80,
        400,
        warn_notifier(test),
        timeout_notifier(test)
      )

    Process.sleep(40)
    assert :ok = EscalatingWatchdog.heartbeat(:w)

    refute_receive {:warned, :w}, 60
  end