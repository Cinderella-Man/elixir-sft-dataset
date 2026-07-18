  test "unregistering a pending job prevents it from firing", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)

    assert JobTracker.count("j") == 0
  end