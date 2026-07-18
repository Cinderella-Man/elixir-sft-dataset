  test "cancelled job does not run further attempts", %{rs: rs} do
    :ok =
      RetryScheduler.schedule(
        rs,
        "j",
        @t0,
        {JobSink, :err, [self()]},
        max_attempts: 5,
        base_delay_ms: 10
      )

    tick(rs)
    assert {:ok, :pending, 1} = RetryScheduler.status(rs, "j")

    assert :ok = RetryScheduler.cancel(rs, "j")

    Clock.advance_ms(1_000_000)
    tick(rs)
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
  end