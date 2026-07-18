  test "re-registering a name replaces interval and callback" do
    test = self()

    # First registration: long interval, tag :old.
    :ok = Watchdog.register(:worker, dummy_pid(), 10_000, notifier(test, :old))

    # Replace with a short interval and a different callback tag.
    :ok = Watchdog.register(:worker, dummy_pid(), 60, notifier(test, :new))

    # The new (short) registration must fire...
    assert_receive {:new, :worker}, 1_000
    # ...and the old callback must never fire.
    refute_receive {:old, :worker}, 100
  end