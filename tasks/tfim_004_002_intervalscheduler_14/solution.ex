  test "unregistered jobs do not fire", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "j", {:every, 1, :seconds}, {JobSink, :ping, [self(), :f]})

    :ok = IntervalScheduler.unregister(is, "j")

    Clock.advance_seconds(10)
    tick(is)
    refute_received :f
  end