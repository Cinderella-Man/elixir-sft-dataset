  test "default max_attempts, base_delay_ms and backoff_factor drive backoff and death",
       %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]})

    # Attempt 1 fails; default base_delay_ms (1_000) schedules the first retry.
    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")
    [{_, :pending, next1, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next1, @t0, :millisecond) == 1_000

    # Attempt 2 fails; default backoff_factor (2.0) makes the next delay 2_000.
    Clock.advance_ms(1_000)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")
    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 3_000

    # Attempt 3 fails; default max_attempts (3) is the total, so the job dies.
    Clock.advance_ms(2_000)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")
  end