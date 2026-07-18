  test "jobs lists a completed job with a next_attempt_at timestamp", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)
    assert_received :ran

    assert [{"j", :completed, %NaiveDateTime{}, 1}] = RetryScheduler.jobs(rs)
  end