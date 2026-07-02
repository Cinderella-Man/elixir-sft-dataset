  test "duplicate names rejected", %{cs: cs} do
    :ok =
      CalendarScheduler.register(
        cs,
        "j",
        {:nth_day_of_month, 1, {0, 0}},
        {JobSink, :ping, [self(), :j]}
      )

    assert {:error, :already_exists} =
             CalendarScheduler.register(
               cs,
               "j",
               {:last_day_of_month, {0, 0}},
               {JobSink, :ping, [self(), :j]}
             )
  end