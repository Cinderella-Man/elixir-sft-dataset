  test "a value-equal composite name replaces instead of duplicating" do
    test = self()
    :ok = Watchdog.register({:svc, [1, 2]}, dummy_pid(), 60, notifier(test, :old))

    # Same name by value, built independently.
    key = {:svc, Enum.to_list(1..2)}
    :ok = Watchdog.register(key, dummy_pid(), 60, notifier(test, :new))

    assert_receive {:new, {:svc, [1, 2]}}, 1_000
    refute_receive {:old, {:svc, [1, 2]}}, 200
    refute_receive {:new, {:svc, [1, 2]}}, 200
  end