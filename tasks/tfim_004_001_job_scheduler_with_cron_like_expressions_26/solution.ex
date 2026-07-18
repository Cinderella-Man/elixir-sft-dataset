  test "range expression 1-3 in hour field", %{s: s} do
    :ok = Scheduler.register(s, "j", "0 1-3 * * *", {JobTracker, :record, ["j"]})

    # From 10:00, next match is 1:00 tomorrow (hours 1,2,3 have passed today)
    assert {:ok, next} = Scheduler.next_run(s, "j")
    assert next.hour in [1, 2, 3]
    assert next.minute == 0
    # Should be tomorrow since 1-3 are all before 10
    assert NaiveDateTime.compare(next, @start_time) == :gt
  end