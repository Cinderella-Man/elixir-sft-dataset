  test "backoff_factor of exactly 1.0 is accepted and keeps delays constant", %{rs: rs} do
    assert :ok =
             RetryScheduler.schedule(
               rs,
               "j",
               @t0,
               {JobSink, :err, [self()]},
               max_attempts: 4,
               base_delay_ms: 50,
               backoff_factor: 1.0
             )

    tick(rs)
    [{_, :pending, next1, 1}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next1, @t0, :millisecond) == 50

    Clock.advance_ms(50)
    tick(rs)
    [{_, :pending, next2, 2}] = RetryScheduler.jobs(rs)
    assert NaiveDateTime.diff(next2, @t0, :millisecond) == 100
  end