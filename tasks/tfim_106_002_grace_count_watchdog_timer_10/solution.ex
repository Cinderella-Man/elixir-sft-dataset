  test "fires exactly once then stops" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 40, 2, notifier(test))

    assert_receive {:timed_out, :w, 2}, 1_000
    refute_receive {:timed_out, :w, _}, 200
  end