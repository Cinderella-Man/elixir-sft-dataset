  test "tick fires a job whose next_run equals now exactly", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :fired]}
      )

    {:ok, first} = CalendarScheduler.next_run(cs, "j")
    assert first == ~N[2025-02-01 00:00:00]

    # Clock lands exactly on next_run — the <= boundary must fire.
    Clock.set(~N[2025-02-01 00:00:00])
    tick(cs)
    assert_received :fired
  end