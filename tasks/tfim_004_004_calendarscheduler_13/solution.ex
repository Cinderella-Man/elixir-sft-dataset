    test "last Friday of Jan 2025 is Jan 31 (a Friday)", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_weekday_of_month, :friday, {17, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 17:00:00]
    end