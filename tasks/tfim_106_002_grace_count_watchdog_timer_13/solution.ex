  test "unregister prevents the callback from firing" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))
    assert :ok = GraceWatchdog.unregister(:w)

    refute_receive {:timed_out, :w, _}, 300
  end