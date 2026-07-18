  test "replacing a registration with a longer interval retires the old short timer" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :old))
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :new))

    # The replaced 50 ms deadline must never fire, and the fresh 10 s one is far away.
    refute_receive {:old, :w}, 300
    refute_receive {:new, :w}, 100
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end