  test "register returns error for too few fields", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "*/5 * *", {IO, :puts, ["hi"]})
  end