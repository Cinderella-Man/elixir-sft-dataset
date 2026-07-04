  test "returning :ok counts as success", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    tick(rs)

    assert_received :ran
    assert {:ok, :completed, 1} = RetryScheduler.status(rs, "j")
  end