    test "last day of Feb 2024 is the 29th (leap year)", %{cs: cs} do
      Clock.set(~N[2024-02-01 00:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:last_day_of_month, {12, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2024-02-29 12:00:00]
    end