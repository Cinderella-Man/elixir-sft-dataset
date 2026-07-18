  test "thrown values count as failure, scheduler survives", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :throw_value, []}, max_attempts: 1)
    tick(rs)

    assert Process.alive?(rs)
    assert {:ok, :dead, 1} = RetryScheduler.status(rs, "j")
  end