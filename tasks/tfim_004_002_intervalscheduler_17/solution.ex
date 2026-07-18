  test "jobs/1 tuples carry the interval_spec and a NaiveDateTime next_run", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "a",
        {:every, 10, :seconds},
        {JobSink, :ping, [self(), :a]}
      )

    assert [{"a", spec, next}] = IntervalScheduler.jobs(is)
    assert spec == {:every, 10, :seconds}
    assert %NaiveDateTime{} = next
    assert NaiveDateTime.compare(next, NaiveDateTime.add(@t0, 10, :second)) == :eq
  end