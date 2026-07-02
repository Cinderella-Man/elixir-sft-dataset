  test "schedule with valid args returns :ok", %{rs: rs} do
    assert :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
    assert {:ok, :pending, 0} = RetryScheduler.status(rs, "j")
  end