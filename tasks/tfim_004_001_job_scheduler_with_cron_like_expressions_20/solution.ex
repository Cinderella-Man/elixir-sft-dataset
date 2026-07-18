  test "job recurs correctly after firing", %{s: s} do
    # Every hour at minute 0
    :ok = Scheduler.register(s, "j", "0 * * * *", {JobTracker, :record, ["j"]})

    # Fire at 11:00
    Clock.set(~N[2026-01-05 11:00:00])
    tick(s)
    assert JobTracker.count("j") == 1

    # After firing, next_run should advance to 12:00
    assert {:ok, ~N[2026-01-05 12:00:00]} = Scheduler.next_run(s, "j")

    # Fire again at 12:00
    Clock.set(~N[2026-01-05 12:00:00])
    tick(s)
    assert JobTracker.count("j") == 2
  end