  test "start_link registers the process under the given :name", %{is: _is} do
    {:ok, _pid} =
      IntervalScheduler.start_link(
        clock: &Clock.now/0,
        tick_interval_ms: :infinity,
        name: :named_scheduler
      )

    assert :ok =
             IntervalScheduler.register(
               :named_scheduler,
               "j",
               {:every, 5, :seconds},
               {JobSink, :ping, [self(), :n]}
             )

    assert {:ok, next} = IntervalScheduler.next_run(:named_scheduler, "j")
    assert NaiveDateTime.compare(next, NaiveDateTime.add(@t0, 5, :second)) == :eq
  end