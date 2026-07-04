  test "steady-state drift-free alignment across many ticks", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 10, :seconds}, {JobSink, :ping, [self(), :f]})

    # Run for 5 intervals, each with slight tick latency.
    for i <- 1..5 do
      Clock.advance_seconds(11)
      tick(is)
      assert_received :f

      # next_run should remain aligned to t0 + i*10*10... wait.  Each iteration
      # advances by 11s, so after iteration i the clock is at t0 + i*11s.  The
      # next_run is the smallest t0 + N*10 > now = t0 + i*11:
      #   N = div(i*11, 10) + 1
      {:ok, next} = IntervalScheduler.next_run(is, "j")
      expected_n = div(i * 11, 10) + 1
      expected = NaiveDateTime.add(@t0, expected_n * 10, :second)
      assert NaiveDateTime.compare(next, expected) == :eq
    end
  end