  test "callback receives the registered name" do
    test = self()
    :ok = Watchdog.register({:svc, 42}, dummy_pid(), 50, notifier(test))

    assert_receive {:timed_out, {:svc, 42}}, 1_000
  end