  test "unregister for a name that was never registered returns :ok" do
    assert :ok = GraceWatchdog.unregister(:nope)

    # The watchdog stays usable afterwards: a fresh registration still fires.
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test))
    assert_receive {:timed_out, :w, 1}, 1_000
  end