  test "phase transitions from healthy to warned" do
    test = self()

    :ok =
      EscalatingWatchdog.register(:w, dummy_pid(), 50, 10_000, warn_notifier(test), timeout_notifier(test))

    assert {:ok, :healthy} = EscalatingWatchdog.phase(:w)
    assert_receive {:warned, :w}, 1_000
    assert {:ok, :warned} = EscalatingWatchdog.phase(:w)
  end