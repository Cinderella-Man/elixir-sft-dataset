  test "every-minute job fires each minute", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    Clock.set(~N[2026-01-05 10:01:00])
    tick(s)
    assert JobTracker.count("j") == 1

    Clock.set(~N[2026-01-05 10:02:00])
    tick(s)
    assert JobTracker.count("j") == 2

    Clock.set(~N[2026-01-05 10:03:00])
    tick(s)
    assert JobTracker.count("j") == 3
  end