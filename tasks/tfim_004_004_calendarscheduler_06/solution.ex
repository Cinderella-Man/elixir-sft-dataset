  test "job fires on tick when due, recomputes for next month", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    # Initial next_run: Feb 1 2025 00:00 (since clock is Jan 1 00:00 and we need strictly >).
    {:ok, first_next} = CalendarScheduler.next_run(cs, "j")
    assert first_next == ~N[2025-02-01 00:00:00]

    # Advance clock past Feb 1
    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :fired

    # Next run should now be Mar 1
    {:ok, next2} = CalendarScheduler.next_run(cs, "j")
    assert next2 == ~N[2025-03-01 00:00:00]
  end