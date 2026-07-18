  test "a name freed by cancelling a terminal job can be scheduled again", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
    assert_received :ran

    assert :ok = RetryScheduler.cancel(rs, "j")
    assert :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")
  end