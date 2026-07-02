  test "fires only after max_misses consecutive missed intervals" do
    test = self()
    :ok = GraceWatchdog.register(:w, dummy_pid(), 50, 3, notifier(test))

    # With interval 50 and threshold 3, the earliest fire is ~150ms.
    refute_receive {:timed_out, :w, _}, 100
    assert_receive {:timed_out, :w, 3}, 1_000
  end