  test "register returns error for duplicate name", %{s: s} do
    :ok = Scheduler.register(s, "j", "* * * * *", {JobTracker, :record, ["j"]})

    assert {:error, :already_exists} =
             Scheduler.register(s, "j", "*/5 * * * *", {JobTracker, :record, ["j"]})
  end