  test "minutes, hours, days intervals work", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "m", {:every, 5, :minutes}, {JobSink, :ping, [self(), :m]})

    :ok = IntervalScheduler.register(is, "h", {:every, 2, :hours}, {JobSink, :ping, [self(), :h]})
    :ok = IntervalScheduler.register(is, "d", {:every, 1, :days}, {JobSink, :ping, [self(), :d]})

    {:ok, m_next} = IntervalScheduler.next_run(is, "m")
    {:ok, h_next} = IntervalScheduler.next_run(is, "h")
    {:ok, d_next} = IntervalScheduler.next_run(is, "d")

    assert NaiveDateTime.diff(m_next, @t0, :second) == 300
    assert NaiveDateTime.diff(h_next, @t0, :second) == 7_200
    assert NaiveDateTime.diff(d_next, @t0, :second) == 86_400
  end