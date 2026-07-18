  test "day-of-week job fires on the correct day", %{s: s} do
    # Wednesday = 3. Next Wednesday from Mon Jan 5 is Jan 7.
    :ok = Scheduler.register(s, "j", "0 12 * * 3", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-07 12:00:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-07 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next should be the following Wednesday, Jan 14
    assert {:ok, ~N[2026-01-14 12:00:00]} = Scheduler.next_run(s, "j")
  end