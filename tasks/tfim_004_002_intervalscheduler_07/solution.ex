  test "jobs whose next_run is <= now are executed on tick", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "j",
        {:every, 10, :seconds},
        {JobSink, :ping, [self(), :fired]}
      )

    # Before t0+10: not yet due
    Clock.advance_seconds(5)
    tick(is)
    refute_received :fired

    # At exactly t0+10: due
    Clock.advance_seconds(5)
    tick(is)
    assert_received :fired
  end