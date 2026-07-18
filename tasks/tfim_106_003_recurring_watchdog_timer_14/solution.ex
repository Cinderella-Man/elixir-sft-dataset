  test "unregister before the first alert cancels the armed timer" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 200, notifier(test))
    assert :ok = RecurringWatchdog.unregister(:w)

    refute_receive {:alert, :w}, 500
    assert {:error, :not_registered} = RecurringWatchdog.status(:w)
  end