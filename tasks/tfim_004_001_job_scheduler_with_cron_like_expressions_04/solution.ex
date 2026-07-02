  test "register returns error for out-of-range minute (60)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "60 * * * *", {IO, :puts, ["hi"]})
  end