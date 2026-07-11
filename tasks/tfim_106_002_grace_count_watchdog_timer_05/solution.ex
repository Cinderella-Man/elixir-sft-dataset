  test "callback receives the name and the miss count" do
    test = self()
    :ok = GraceWatchdog.register({:svc, 1}, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, {:svc, 1}, 2}, 1_000
  end