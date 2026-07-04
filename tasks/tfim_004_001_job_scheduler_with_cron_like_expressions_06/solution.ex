  test "register returns error for out-of-range day-of-week (7)", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "bad", "0 0 * * 7", {IO, :puts, ["hi"]})
  end