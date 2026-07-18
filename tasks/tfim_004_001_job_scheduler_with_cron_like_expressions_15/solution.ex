  test "next_run wraps to next day when time has passed", %{s: s} do
    # At 10:00, "0 9 * * *" (9:00) already passed today → next is tomorrow
    :ok = Scheduler.register(s, "j", "0 9 * * *", {JobTracker, :record, ["j"]})
    assert {:ok, ~N[2026-01-06 09:00:00]} = Scheduler.next_run(s, "j")
  end