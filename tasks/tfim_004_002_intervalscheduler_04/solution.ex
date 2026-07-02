  test "rejects malformed interval specs with :invalid_interval", %{is: is} do
    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "a",
               {:every, 0, :seconds},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "b",
               {:every, -5, :seconds},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "c",
               {:every, 5, :fortnights},
               {JobSink, :ping, [self(), :x]}
             )

    assert {:error, :invalid_interval} =
             IntervalScheduler.register(
               is,
               "d",
               "every 5 seconds",
               {JobSink, :ping, [self(), :x]}
             )
  end