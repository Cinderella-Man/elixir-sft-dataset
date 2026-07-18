  test "next_run returns the correct next datetime for a specific time", %{s: s} do
    # At 10:00, next "30 11 * * *" is today at 11:30
    :ok = Scheduler.register(s, "j", "30 11 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-05 11:30:00]} = Scheduler.next_run(s, "j")
  end