  test "callback receives the registered name" do
    test = self()
    :ok = RecurringWatchdog.register({:svc, 7}, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, {:svc, 7}}, 1_000
  end