  test "a crashing job does not kill the scheduler", %{is: is} do
    :ok = IntervalScheduler.register(is, "bad", {:every, 1, :seconds}, {JobSink, :crash, []})

    :ok =
      IntervalScheduler.register(
        is,
        "good",
        {:every, 1, :seconds},
        {JobSink, :ping, [self(), :g]}
      )

    Clock.advance_seconds(1)
    tick(is)

    # Scheduler survived — good job still fired
    assert_received :g
    assert Process.alive?(is)

    # And the bad job is still registered; its next_run has advanced.
    {:ok, bad_next} = IntervalScheduler.next_run(is, "bad")
    assert NaiveDateTime.compare(bad_next, Clock.now()) == :gt
  end