  test "jobs/1 returns empty list when no jobs registered", %{s: s} do
    assert Scheduler.jobs(s) == []
  end