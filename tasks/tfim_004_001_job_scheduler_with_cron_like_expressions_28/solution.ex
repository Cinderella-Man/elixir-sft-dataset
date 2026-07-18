  test "range with step 10-30/10 matches 10, 20, 30", %{s: s} do
    :ok = Scheduler.register(s, "j", "10-30/10 * * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next is 10:10
    assert {:ok, ~N[2026-01-05 10:10:00]} = Scheduler.next_run(s, "j")

    # Fire at 10:10, next should be 10:20
    Clock.set(~N[2026-01-05 10:10:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:20:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 1

    # Fire at 10:20, next should be 10:30
    Clock.set(~N[2026-01-05 10:20:00])
    tick(s)
    assert {:ok, ~N[2026-01-05 10:30:00]} = Scheduler.next_run(s, "j")
    assert JobTracker.count("j") == 2
  end