  test "a job that throws does not kill the scheduler", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "thrower",
        {:nth_day_of_month, 1, {0, 0}},
        {:erlang, :throw, [:boom]}
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

    # A throw is only swallowed by the `catch` clause, not `rescue`.
    assert_received :ok
    assert Process.alive?(cs)

    {:ok, next} = CalendarScheduler.next_run(cs, "thrower")
    assert next == ~N[2025-03-01 00:00:00]
  end