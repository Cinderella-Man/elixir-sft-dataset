  test "invalid opts return :invalid_opts", %{rs: rs} do
    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "a", @t0, {JobSink, :ok, [self()]}, max_attempts: 0)

    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "b", @t0, {JobSink, :ok, [self()]}, backoff_factor: 0.5)

    assert {:error, :invalid_opts} =
             RetryScheduler.schedule(rs, "c", @t0, {JobSink, :ok, [self()]}, base_delay_ms: -1)
  end