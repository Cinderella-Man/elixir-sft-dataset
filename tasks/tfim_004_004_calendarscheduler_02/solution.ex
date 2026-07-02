  test "valid rules return :ok at registration", %{cs: cs} do
    assert :ok =
             CalendarScheduler.register(
               cs,
               "a",
               {:nth_weekday_of_month, 1, :monday, {9, 0}},
               {JobSink, :ping, [self(), :a]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "b",
               {:last_weekday_of_month, :friday, {17, 0}},
               {JobSink, :ping, [self(), :b]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "c",
               {:nth_day_of_month, 15, {12, 0}},
               {JobSink, :ping, [self(), :c]}
             )

    assert :ok =
             CalendarScheduler.register(
               cs,
               "d",
               {:last_day_of_month, {23, 59}},
               {JobSink, :ping, [self(), :d]}
             )
  end