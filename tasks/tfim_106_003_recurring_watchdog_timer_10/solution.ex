  test "heartbeat and status for unknown names" do
    assert :ok = RecurringWatchdog.heartbeat(:nope)
    assert {:error, :not_registered} = RecurringWatchdog.status(:nope)
  end