  test "jobs/1 lists all registered jobs", %{s: s} do
    :ok = Scheduler.register(s, "j1", "30 11 * * *", {JobTracker, :record, ["j1"]})
    :ok = Scheduler.register(s, "j2", "0 12 * * *", {JobTracker, :record, ["j2"]})

    jobs = Scheduler.jobs(s)
    names = jobs |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    assert names == ["j1", "j2"]
  end