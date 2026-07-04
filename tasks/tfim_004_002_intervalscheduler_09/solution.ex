  test "a late tick does NOT push future runs further out", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

    # Tick arrives 1 second late (at t0 + 61s)
    Clock.advance_seconds(61)
    tick(is)
    assert_received :f

    # Next run must be t0 + 120s, NOT t0 + 121s (naive now-based scheduling would drift)
    {:ok, next} = IntervalScheduler.next_run(is, "j")
    expected = NaiveDateTime.add(@t0, 120, :second)
    assert NaiveDateTime.compare(next, expected) == :eq
  end