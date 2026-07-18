  test "re-registering with longer deadlines defers past the old deadlines" do
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

    :ok =
      EscalatingWatchdog.register(
        :w,
        dummy_pid(),
        5_000,
        10_000,
        warn_notifier(test),
        timeout_notifier(test)
      )

    # The replaced 40/90 deadlines must be dead: drive real time well past both.
    refute_receive {:warned, :w}, 250
    refute_receive {:timed_out, :w}, 10
    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)
    assert :ok = EscalatingWatchdog.unregister(:w)
  end