  test "timeout removes the registration and does not fire again" do
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

    assert_receive {:timed_out, :w}, 1_000
    assert {:error, :not_registered} = EscalatingWatchdog.phase(:w)
    refute_receive {:timed_out, :w}, 200
  end