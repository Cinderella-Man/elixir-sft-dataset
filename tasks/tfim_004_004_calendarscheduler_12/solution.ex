    test "advances to next month after the target passes", %{cs: cs} do
      :ok =
        CalendarScheduler.register(
          cs,
          "j",
          {:nth_weekday_of_month, 1, :monday, {9, 0}},
          {JobSink, :ping, [self(), :j]}
        )

      # Set clock to Jan 7 (past Jan 6's Monday) — should skip to Feb
      Clock.set(~N[2025-01-07 00:00:00])
      tick(cs)

      {:ok, next} = CalendarScheduler.next_run(cs, "j")
      # Feb 1 2025 = Sat; first Monday is Feb 3.
      assert next == ~N[2025-02-03 09:00:00]
    end