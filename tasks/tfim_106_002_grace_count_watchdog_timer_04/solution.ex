  test "max_misses of 1 fires after a single missed interval" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 1, notifier(test))

    assert_receive {:timed_out, :w, 1}, 1_000
  end