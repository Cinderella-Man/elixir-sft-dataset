  test "status becomes alerting after the first miss and healthy again after a heartbeat" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:w)

    assert :ok = RecurringWatchdog.heartbeat(:w)
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
  end