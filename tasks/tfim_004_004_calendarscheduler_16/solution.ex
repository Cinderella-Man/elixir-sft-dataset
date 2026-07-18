    test "31st skips February (no Feb 31)", %{cs: cs} do
      Clock.set(~N[2025-01-31 23:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_day_of_month, 31, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      # Jan 31 12:00 is already past (clock is Jan 31 23:00).
      # Feb has no 31 → skip.  March has 31 → Mar 31 12:00.
      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-03-31 12:00:00]
    end