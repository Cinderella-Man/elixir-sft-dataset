  test "multiple due jobs all fire on a single tick", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "a",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :a]}
      )

    :ok =
      CalendarScheduler.register(
        cs,
        "b",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :b]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)

    assert_received :a
    assert_received :b
  end