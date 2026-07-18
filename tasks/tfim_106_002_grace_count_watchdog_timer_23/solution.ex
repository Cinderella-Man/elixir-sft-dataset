  test "a burst of misses interrupted by a heartbeat does not fire at the original deadline" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 60, 3, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 100, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert :ok = GraceWatchdog.heartbeat(:w)
    assert {:ok, 0} = GraceWatchdog.misses(:w)

    # The threshold would have been crossed by ~180ms without the heartbeat.
    refute_receive {:timed_out, :w, _}, 120
  end