  test "register returns error for out-of-range hour (25)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 25 * * *", {IO, :puts, ["hi"]})
  end