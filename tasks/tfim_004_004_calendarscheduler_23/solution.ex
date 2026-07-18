  test "registration at exactly the target time skips to the next month", %{cs: cs} do
    # Clock sits exactly on the first Monday's target instant.
    Clock.set(~N[2025-01-06 09:00:00])

    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_weekday_of_month, 1, :monday, {9, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    # Equal is not strictly greater, so Jan 6 must be skipped for Feb 3.
    {:ok, next} = CalendarScheduler.next_run(cs, "j")
    assert next == ~N[2025-02-03 09:00:00]
  end