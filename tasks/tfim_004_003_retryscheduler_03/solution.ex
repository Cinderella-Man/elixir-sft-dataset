  test "duplicate name returns :already_exists", %{rs: rs} do
    :ok = RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})

    assert {:error, :already_exists} =
             RetryScheduler.schedule(rs, "j", @t0, {JobSink, :ok, [self()]})
  end