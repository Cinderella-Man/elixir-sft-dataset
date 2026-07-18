  test "first retry uses base_delay_ms", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 3,
        base_delay_ms: 1_000,
        backoff_factor: 2.0
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # First retry should be scheduled base_delay_ms (1000ms) after now
    [{_, :pending, next, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next, @t0, :millisecond) == 1_000
  end