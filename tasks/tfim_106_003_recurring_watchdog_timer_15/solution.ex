  test "heartbeat and unregister on one name leave another name alerting" do
    test = self()
    :ok = RecurringWatchdog.register(:a, dummy_pid(), 10_000, notifier(test, :a_alert))
    :ok = RecurringWatchdog.register(:b, dummy_pid(), 50, notifier(test, :b_alert))

    assert :ok = RecurringWatchdog.heartbeat(:a)
    assert :ok = RecurringWatchdog.unregister(:a)

    assert_receive {:b_alert, :b}, 1_000
    assert_receive {:b_alert, :b}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:b)
    refute_receive {:a_alert, :a}, 50
  end