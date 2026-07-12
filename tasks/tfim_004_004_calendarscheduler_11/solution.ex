    test "second Tuesday of Jan 2025", %{cs: cs} do
      # Jan 1 2025 = Wed.  Tuesdays: Jan 7, Jan 14, Jan 21, Jan 28.
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 2, :tuesday, {10, 30}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-14 10:30:00]
    end