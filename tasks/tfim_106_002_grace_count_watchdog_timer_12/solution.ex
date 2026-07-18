  test "re-registering replaces interval, threshold and callback" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 10_000, 5, notifier(test, :old))
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test, :new))

    assert_receive {:new, :w, 1}, 1_000
    refute_receive {:old, :w, _}, 100
  end