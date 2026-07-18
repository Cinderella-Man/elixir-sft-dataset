  test "job transitions to :dead after max_attempts failures", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 3,
        base_delay_ms: 10,
        backoff_factor: 2.0
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    Clock.advance_ms(10)
    tick(rs)
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    Clock.advance_ms(20)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")

    # Further ticks do NOT re-execute a :dead job
    Clock.advance_ms(1_000_000)
    tick(rs)
    assert {:ok, :dead, 3} = RetryScheduler.status(rs, "j")
  end