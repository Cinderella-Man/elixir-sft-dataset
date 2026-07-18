    test "last day of Jan 2025 is the 31st", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_day_of_month, {23, 59}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-31 23:59:00]
    end