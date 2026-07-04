  test "unregister returns :ok for an existing job", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})
    assert :ok = Scheduler.unregister(s, "j")
  end