  test "a heartbeat for one name does not reset another name's timer" do
    test = self()
    :ok = Watchdog.register(:chatty, dummy_pid(), 10_000, notifier(test, :chatty_out))
    :ok = Watchdog.register(:quiet, dummy_pid(), 60, notifier(test, :quiet_out))

    # Heartbeats for :chatty must not touch :quiet's armed timer.
    for _ <- 1..5 do
      assert :ok = Watchdog.heartbeat(:chatty)
    end

    assert_receive {:quiet_out, :quiet}, 1_000
    refute_receive {:chatty_out, :chatty}, 50
  end