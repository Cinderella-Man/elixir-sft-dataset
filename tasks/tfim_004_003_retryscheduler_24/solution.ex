  test "cancel removes a :dead job", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]}, max_attempts: 1)
    tick(rs)
    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")

    assert :ok = RetryScheduler.cancel(rs, "j")
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
    assert [] = RetryScheduler.jobs(rs)
  end