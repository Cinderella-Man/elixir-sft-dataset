  test "a job that fails twice then succeeds ends :completed with 3 attempts", %{rs: rs} do
    start_supervised!({Flaky, 2})

    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {Flaky, :attempt, [self()]},
        max_attempts: 5,
        base_delay_ms: 10,
        backoff_factor: 2.0
      )

    # Attempt 1 fails
    tick(rs)
    assert_received {:flaky_attempt, 1}
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    # Attempt 2 fails (after 10ms backoff)
    Clock.advance_ms(10)
    tick(rs)
    assert_received {:flaky_attempt, 2}
    assert {:ok, :pending, 2} = RetryScheduler.status(rs, "j")

    # Attempt 3 succeeds (after 20ms backoff)
    Clock.advance_ms(20)
    tick(rs)
    assert_received {:flaky_attempt, 3}
    assert {:ok, :completed, 3} = RetryScheduler.status(rs, "j")

    # Further ticks don't re-run a :completed job
    Clock.advance_ms(1_000_000)
    tick(rs)
    refute_received {:flaky_attempt, _}
  end