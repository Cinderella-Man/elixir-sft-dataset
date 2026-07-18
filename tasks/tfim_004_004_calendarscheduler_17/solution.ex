    test "31st also skips April (only 30 days), June, September, November", %{cs: cs} do
      Clock.set(~N[2025-03-31 23:00:00])

      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_day_of_month, 31, {0, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      # Mar 31 00:00 already past.  Apr has 30 → skip.  May 31 exists.
      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      assert next == ~N[2025-05-31 00:00:00]
    end