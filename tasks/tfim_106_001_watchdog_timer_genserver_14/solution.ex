  test "re-registering re-arms the timer with a fresh clock" do
    test = self()

    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))
    Process.sleep(120)
    # Re-register before the first interval elapses; clock restarts.
    :ok = Watchdog.register(:worker, dummy_pid(), 200, notifier(test))

    # 120ms after re-registration is still under the 200ms interval.
    refute_receive {:timed_out, :worker}, 120

    # Eventually it should fire from the fresh registration.
    assert_receive {:timed_out, :worker}, 1_000
  end