  test "steady heartbeats keep the miss count at zero so it never fires" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 60, 2, notifier(test))

    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = GraceWatchdog.heartbeat(:w)
    end

    refute_receive {:timed_out, :w, _}, 40
  end