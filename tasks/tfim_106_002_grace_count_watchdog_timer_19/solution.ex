  test "the registration is removed once the callback has fired" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 1, notifier(test))

    assert_receive {:timed_out, :w, 1}, 1_000
    assert {:error, :not_registered} = GraceWatchdog.misses(:w)
  end