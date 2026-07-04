  test "next_run rolls from December to January of the next year", %{cs: cs} do
    Clock.set(~N[2025-12-31 23:59:30])

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2026-01-01 00:00:00]
  end