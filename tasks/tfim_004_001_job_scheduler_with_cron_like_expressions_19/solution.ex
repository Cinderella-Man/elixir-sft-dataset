  test "job does not fire twice on the same tick", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:30:00])
    tick(s)
    tick(s)

    assert JobTracker.count("j") == 1
  end