  test "auto-ticking keeps firing, so a job due later still runs" do
    {:ok, rs} = RetryScheduler.start_link(clock: &Clock.now/0, tick_interval_ms: 10)

    future = NaiveDateTime.add(@t0, 60, :second)
    :ok = RetryScheduler.schedule(rs, "j", future, {JobSink, :ok, [self()]})

    # Early ticks find the job not yet due and must leave it alone.
    refute_receive :ran, 150
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    # Once the clock passes run_at, a later tick must still arrive: the
    # scheduler re-arms its timer after every tick.
    Clock.advance_ms(60_001)
    assert_receive :ran, 2_000
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end