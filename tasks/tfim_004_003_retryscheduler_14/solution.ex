  test "retry delays follow base * factor^(n-1)", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 4,
        base_delay_ms: 100,
        backoff_factor: 2.0
      )

    # Attempt 1 (fails at t=0) → retry scheduled at t=100ms
    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # Jump to retry 1 — fails → retry scheduled at t=100 + 200 = 300ms
    Clock.advance_ms(100)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 100 + 200

    # Jump to retry 2 — fails → retry scheduled base*factor^2 = 400ms later
    Clock.advance_ms(200)
    tick(rs)
    assert {:ok, :pending, 3} = RetryScheduler.status(rs, "j")

    [{_, :pending, next3, 3}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next3, @t0, :millisecond) == 700
  end