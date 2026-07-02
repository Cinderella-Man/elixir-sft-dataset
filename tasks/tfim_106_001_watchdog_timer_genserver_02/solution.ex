  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = Watchdog.register(:worker, dummy_pid(), 120, notifier(test))

    # Heartbeat every 40ms, well under the 120ms interval.
    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = Watchdog.heartbeat(:worker)
    end

    # After the last heartbeat, less than one interval has elapsed.
    refute_receive {:timed_out, :worker}, 60
  end