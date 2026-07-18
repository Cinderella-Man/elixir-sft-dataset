  test "step expression */15 fires at 0, 15, 30, 45", %{s: s} do
    :ok = Scheduler.register(s, "j", "*/15 * * * *", {JobTracker, :record, ["j"]})

    for minute <- [0, 15, 30, 45] do
      Clock.set(~N[2026-01-05 11:00:00] |> NaiveDateTime.add(minute * 60, :second))
      tick(s)
    end

    assert JobTracker.count("j") == 4
  end