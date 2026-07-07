  test "neither phase fires while heartbeats arrive within warn_ms" do
    test = self()

    :ok =
      EscalatingWatchdog.register(
        :w, dummy_pid(), 80, 200, warn_notifier(test), timeout_notifier(test)
      )

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = EscalatingWatchdog.heartbeat(:w)
    end

    refute_receive {:warned, :w}, 60
    refute_receive {:timed_out, :w}, 10
  end