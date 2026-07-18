  test "unregistering the same name twice is a no-op the second time" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert :ok = GraceWatchdog.unregister(:w)
    assert :ok = GraceWatchdog.unregister(:w)
    assert {:error, :not_registered} = GraceWatchdog.misses(:w)

    refute_receive {:timed_out, :w, _}, 300
  end