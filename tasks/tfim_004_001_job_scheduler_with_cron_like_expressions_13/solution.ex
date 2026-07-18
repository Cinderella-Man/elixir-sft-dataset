  test "register accepts February 29th (satisfiable via leap years)", %{s: s} do
    assert :ok = Scheduler.register(s, "leap", "0 0 29 2 *", {JobTracker, :record, ["leap"]})
  end