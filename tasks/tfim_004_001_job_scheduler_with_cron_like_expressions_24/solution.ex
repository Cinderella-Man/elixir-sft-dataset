  test "re-registering after unregister works", %{s: s} do
    :ok = Scheduler.register(s, "j", "30 10 * * *", {JobTracker, :record, ["j"]})
    :ok = Scheduler.unregister(s, "j")
    :ok = Scheduler.register(s, "j", "45 10 * * *", {JobTracker, :record, ["j"]})

    assert {:ok, ~N[2026-01-05 10:45:00]} = Scheduler.next_run(s, "j")

    Clock.set(~N[2026-01-05 10:45:00])
    tick(s)
    assert JobTracker.count("j") == 1
  end