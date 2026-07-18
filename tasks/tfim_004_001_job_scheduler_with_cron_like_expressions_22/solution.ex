  test "two jobs scheduled for the same time both fire", %{s: s} do
    :ok = Scheduler.register(s, "a", "30 10 * * *", {JobTracker, :record, ["a"]})
    :ok = Scheduler.register(s, "b", "30 10 * * *", {JobTracker, :record, ["b"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("a") == 1
    assert JobTracker.count("b") == 1
  end