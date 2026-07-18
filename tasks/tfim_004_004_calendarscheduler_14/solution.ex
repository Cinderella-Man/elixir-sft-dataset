    test "last Sunday of Feb 2025", %{cs: cs} do
      # Feb 28 2025 = Fri.  Last Sunday = Feb 23.
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :sunday, {20, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      Clock.set(~N[2025-02-01 00:00:00])

      # Re-register — next_run is computed at registration time from the clock
      :ok = CalendarScheduler.unregister(cs, "j")

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :sunday, {20, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-02-23 20:00:00]
    end