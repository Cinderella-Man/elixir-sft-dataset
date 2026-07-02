  test "registering a valid interval job returns :ok", %{is: is} do
    assert :ok =
             IntervalScheduler.register(
               is,
               "job1",
               {:every, 10, :seconds},
               {JobSink, :ping, [self(), :j1]}
             )

    assert {:ok, next} = IntervalScheduler.next_run(is, "job1")
    # First fire is started_at + 10s = t0 + 10s
    assert NaiveDateTime.compare(next, NaiveDateTime.add(@t0, 10, :second)) == :eq
  end