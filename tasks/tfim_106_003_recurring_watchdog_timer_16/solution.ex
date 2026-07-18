  test "a dead registered pid stays healthy while heartbeats keep arriving" do
    test = self()
    pid = dummy_pid()
    :ok = RecurringWatchdog.register(:w, pid, 150, notifier(test))

    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 500

    for _ <- 1..4 do
      assert :ok = RecurringWatchdog.heartbeat(:w)
      refute_receive {:alert, :w}, 50
    end

    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end