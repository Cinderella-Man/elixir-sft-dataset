  test "job does not fire before run_at", %{rs: rs} do
    future = NaiveDateTime.add(@t0, 100, :second)
    :ok = RetryScheduler.schedule(rs, "j", future, {JobSink, :ok, [self()]})

    tick(rs)
    refute_received :ran
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")

    # Advance just past run_at
    Clock.advance_ms(100_001)
    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end