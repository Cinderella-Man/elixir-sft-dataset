  test "misses accumulate over intervals and are queryable" do
    :ok = GraceWatchdog.register(:w, dummy_pid(), 80, 5, notifier(self()))

    # One interval elapses (~80ms); at 120ms exactly one miss recorded.
    Process.sleep(120)
    assert {:ok, 1} = GraceWatchdog.misses(:w)
  end