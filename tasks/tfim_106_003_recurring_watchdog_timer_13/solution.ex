  test "replacing an alerting registration resets its health back to healthy" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test, :old))

    assert_receive {:old, :w}, 1_000
    assert {:ok, :alerting} = RecurringWatchdog.status(:w)

    :ok = RecurringWatchdog.register(:w, dummy_pid(), 10_000, notifier(test, :new))
    assert {:ok, :healthy} = RecurringWatchdog.status(:w)
    refute_receive {:old, :w}, 200
    refute_receive {:new, :w}, 50
  end