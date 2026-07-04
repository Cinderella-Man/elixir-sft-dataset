  test "long skip does not replay missed intervals — one fire per tick", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 60, :seconds}, {JobSink, :ping, [self(), :f]})

    # Jump 250 seconds forward — four boundaries (60, 120, 180, 240) missed
    Clock.advance_seconds(250)
    tick(is)

    # Exactly ONE message should be delivered for this tick
    assert_received :f
    refute_received :f

    # Next run is the next boundary after 250s, which is 300s
    {:ok, next} = IntervalScheduler.next_run(is, "j")
    expected = NaiveDateTime.add(@t0, 300, :second)
    assert NaiveDateTime.compare(next, expected) == :eq
  end