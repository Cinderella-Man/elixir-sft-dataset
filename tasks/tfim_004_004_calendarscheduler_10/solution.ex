    test "first Monday of Jan 2025 from Jan 1 is Jan 6", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 1, :monday, {9, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-06 09:00:00]
    end