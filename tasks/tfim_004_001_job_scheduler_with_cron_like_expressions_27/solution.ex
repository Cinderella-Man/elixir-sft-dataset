  test "comma-separated values in minute field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0,30 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:30 (advancing at least 1 minute, minute 0 is behind)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
  end