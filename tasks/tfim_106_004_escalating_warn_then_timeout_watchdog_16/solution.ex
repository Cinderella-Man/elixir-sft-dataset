  test "unregister after the warning prevents the pending timeout" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        200,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    assert :ok = EscalatingWatchdog.unregister(:w)
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:w)

    refute_receive {:timed_out, :w}, 300
  end