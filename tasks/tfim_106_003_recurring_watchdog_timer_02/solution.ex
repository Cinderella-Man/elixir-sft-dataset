  test "stays healthy while heartbeats arrive within the interval" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 100, notifier(test))

    for _ <- 1..4 do
      Process.sleep(40)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 60
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end