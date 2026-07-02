  test "register returns :ok for a valid cron expression", %{s: s} do
    assert :ok = Scheduler.register(s, "job1", "*/5 * * * *", {JobTracker, :record, ["job1"]})
  end