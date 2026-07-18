  test "day-of-week 1 (Monday) schedules to next Monday", %{s: s} do
    # We're on Monday 10:00. Next Monday-matching time at 09:00 is next week.
    :ok = Scheduler.register(s, "j", "0 9 * * 1", {JobTracker, :record, ["j"]})

    # 09:00 today already passed, so next Monday is Jan 12
    assert {:ok, ~N[2026-01-12 09:00:00]} = Scheduler.next_run(s, "j")
  end