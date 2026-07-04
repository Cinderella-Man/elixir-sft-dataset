  test "returning {:error, _} counts as failure", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :err, [self()]}, max_attempts: 1)
    tick(rs)

    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end