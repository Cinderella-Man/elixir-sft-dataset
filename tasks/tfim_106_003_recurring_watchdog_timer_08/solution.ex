  test "unregister stops the recurring alerts" do
    test = self()
    :ok = RecurringWatchdog.register(:w, dummy_pid(), 50, notifier(test))

    assert_receive {:alert, :w}, 1_000
    assert :ok = RecurringWatchdog.unregister(:w)

    refute_receive {:alert, :w}, 300
    assert {:error, :not_registered} = RecurringWatchdog.status(:w)
  end