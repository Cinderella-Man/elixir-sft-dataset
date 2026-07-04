  test "multiple due jobs all fire on one tick", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "a",
        {:every, 5, :seconds},
        {JobSink, :ping, [self(), :a_fired]}
      )

    :ok =
      IntervalScheduler.register(
        is,
        "b",
        {:every, 5, :seconds},
        {JobSink, :ping, [self(), :b_fired]}
      )

    Clock.advance_seconds(5)
    tick(is)

    assert_received :a_fired
    assert_received :b_fired
  end