  test "a server with a finite tick interval runs a due job with no manual tick" do
    {:ok, rs} = RetryScheduler.start_link(clock: &Clock.now/0, tick_interval_ms: 10)

    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    # Nothing but the scheduler's own periodic tick can drive this attempt.
    assert_receive :ran, 2_000
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end