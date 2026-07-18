  test "a heartbeat for one name leaves another name's miss count alone" do
    test = self()
    :ok = GraceWatchdog.register(:a, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:b, dummy_pid(), 25, 10, notifier(test))
    :ok = GraceWatchdog.register(:gate, dummy_pid(), 70, 1, notifier(test, :gate))

    assert_receive {:gate, :gate, 1}, 1_000
    assert :ok = GraceWatchdog.heartbeat(:a)

    assert {:ok, 0} = GraceWatchdog.misses(:a)
    assert {:ok, b_misses} = GraceWatchdog.misses(:b)
    assert b_misses >= 1
  end