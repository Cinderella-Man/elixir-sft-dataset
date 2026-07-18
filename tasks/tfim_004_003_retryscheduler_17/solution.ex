  test "run_at in the past fires on next tick", %{rs: rs} do
    past = NaiveDateTime.add(@t0, -3_600, :second)
    :ok = RetryScheduler.schedule(rs, "j", past, {JobSink, :ok, [self()]})

    tick(rs)
    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end