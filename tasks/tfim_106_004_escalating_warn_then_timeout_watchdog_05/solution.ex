  test "callbacks receive the registered name" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        {:svc, 9},
        dummy_pid(),
        40,
        90,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, {:svc, 9}}, 1_000
    assert_receive {:timed_out, {:svc, 9}}, 1_000
  end