  test "day-of-week 0 (Sunday) schedules to next Sunday", %{s: s} do
    # We start on Monday Jan 5. Next Sunday is Jan 11.
    :ok = Scheduler.register(s, "j", "0 9 * * 0", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-11 09:00:00]} = Scheduler.next_run(s, "j")
  end