  test "crashing job does not kill the scheduler", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "bad",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :crash, []}
      )

    :ok =
      CalendarScheduler.register(
        cs,
        "good",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :ok]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :ok
    assert Process.alive?(cs)

    # Both jobs should still be registered and have advanced next_runs
    {:ok, bad_next} = CalendarScheduler.next_run(cs, "bad")
    assert bad_next == ~N[2025-03-01 00:00:00]
  end