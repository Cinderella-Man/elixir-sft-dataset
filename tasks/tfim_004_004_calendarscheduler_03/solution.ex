  test "invalid rules return :invalid_rule", %{cs: cs} do
    # n out of range (must be 1..4)
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "a",
               {:nth_weekday_of_month, 5, :monday, {9, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # unknown weekday
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "b",
               {:nth_weekday_of_month, 1, :funday, {9, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # hour out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "c",
               {:last_day_of_month, {25, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # minute out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "d",
               {:last_day_of_month, {0, 60}},
               {JobSink, :ping, [self(), :x]}
             )

    # day out of range
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "e",
               {:nth_day_of_month, 32, {0, 0}},
               {JobSink, :ping, [self(), :x]}
             )

    # completely malformed
    assert {:error, :invalid_rule} =
             CalendarScheduler.register(
               cs,
               "f",
               {:random, :nonsense},
               {JobSink, :ping, [self(), :x]}
             )
  end