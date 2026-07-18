    test "15th of January 2025 at noon", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_day_of_month, 15, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-01-15 12:00:00]
    end