  test "overdue job fires once and recomputes next_run relative to now", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    # Registered at Jan 1 → initial next_run is Feb 1 00:00.
    {:ok, first} = CalendarScheduler.next_run(cs, "j")
    assert first == ~N[2025-02-01 00:00:00]

    # Jump far past the deadline; the scheduler never ticked in between.
    Clock.set(~N[2025-04-05 00:00:00])
    tick(cs)

    # Fires exactly once — no catch-up storm for the skipped Mar 1 occurrence.
    assert_received :fired
    refute_received :fired

    # Recomputed relative to *now* (Apr 5), not relative to the old next_run.
    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2025-05-01 00:00:00]
  end