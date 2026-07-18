  test "a second tick at the same clock does not re-fire a skipped job", %{is: is} do
    :ok =
      IntervalScheduler.register(
        is,
        "j",
        {:every, 60, :seconds},
        {JobSink, :ping, [self(), :f]}
      )

    # Jump past four missed boundaries; the single overdue fire happens now.
    Clock.advance_seconds(250)
    tick(is)
    assert_received :f

    # Drive one more tick at the SAME clock: next_run is now T0+300 > now,
    # so the observable effect (a :f message) must NOT happen a second time.
    tick(is)
    refute_received :f

    {:ok, next} = IntervalScheduler.next_run(is, "j")
    expected = NaiveDateTime.add(@t0, 300, :second)
    assert NaiveDateTime.compare(next, expected) == :eq
  end