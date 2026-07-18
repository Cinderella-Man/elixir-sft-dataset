  test "a second tick at the same clock does not fire the job again", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    Clock.set(~N[2025-02-01 00:00:01])
    tick(cs)
    assert_received :fired

    # Clock unchanged; the recomputed next_run is now in the future.
    tick(cs)
    refute_received :fired
  end