  test "register rejects an expression whose day never exists in its month", %{s: s} do
    assert {:error, :invalid_cron} =
             Scheduler.register(s, "apr31", "0 0 31 4 *", {IO, :puts, ["hi"]})

    assert {:error, :invalid_cron} =
             Scheduler.register(s, "feb30", "0 0 30 2 *", {IO, :puts, ["hi"]})
  end