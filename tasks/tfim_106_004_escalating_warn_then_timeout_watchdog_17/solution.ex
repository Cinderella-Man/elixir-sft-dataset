  test "the warning fires only once while the entity stays silent" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        40,
        5_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    assert_receive {:warned, :w}, 1_000
    refute_receive {:warned, :w}, 250
    assert {:ok, :warned} = EscalatingWatchdog.phase(:w)
    assert :ok = EscalatingWatchdog.unregister(:w)
  end