  test "tick_interval_ms :infinity never auto-ticks; only manual ticks run jobs", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    # The job is due immediately, yet auto-ticking is disabled.
    refute_receive :ran, 300
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end