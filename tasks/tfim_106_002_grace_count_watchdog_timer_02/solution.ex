  test "does not fire while heartbeats arrive within the interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 2, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 60
  end