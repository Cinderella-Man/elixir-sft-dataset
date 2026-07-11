  test "a heartbeat resets the accumulated miss count" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
    assert :ok = GraceWatchdog.heartbeat(:w)
    assert {:ok, 0} = GraceWatchdog.misses(:w)
  end