  test "cancel removes a job; unknown cancel returns :not_found", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert :ok = RetryScheduler.cancel(rs, "j")
    assert {:error, :not_found} = RetryScheduler.status(rs, "j")
    assert {:error, :not_found} = RetryScheduler.cancel(rs, "j")
  end