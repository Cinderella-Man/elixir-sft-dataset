  test "unregistering an unknown name leaves other registrations untouched" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert :ok = GraceWatchdog.unregister(:nope)
    assert {:error, :not_registered} = GraceWatchdog.misses(:nope)
    assert {:ok, _} = GraceWatchdog.misses(:w)

    assert_receive {:timed_out, :w, 2}, 1_000
  end