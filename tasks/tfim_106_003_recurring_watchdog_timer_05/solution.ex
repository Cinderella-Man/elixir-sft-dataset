  test "resumed heartbeats silence the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 60, notifier(test))

    assert_receive {:alert, :w}, 1_000

    # Heartbeat steadily, faster than the interval.
    for _ <- 1..5 do
      Process.sleep(30)
      assert :ok = RecurringWatchdog.heartbeat(:w)
    end

    refute_receive {:alert, :w}, 40
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end