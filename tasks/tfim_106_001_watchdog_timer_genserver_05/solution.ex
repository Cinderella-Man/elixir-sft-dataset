  test "heartbeat resets the timer so cumulative uptime exceeds the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 90, notifier(test))

    # Two heartbeats spaced 60ms apart: total 120ms > 90ms interval,
    # but each heartbeat resets the clock so no timeout should occur yet.
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)
    Process.sleep(60)
    assert :ok = Watchdog.heartbeat(:worker)

    refute_receive {:timed_out, :worker}, 40

    # Now stop heartbeating; the timer should eventually fire.
    assert_receive {:timed_out, :worker}, 1_000
  end