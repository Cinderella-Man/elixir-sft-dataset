  test "jobs/1 returns the registered jobs", %{is: is} do
    :ok =
      IntervalScheduler.register(is, "a", {:every, 10, :seconds}, {JobSink, :ping, [self(), :a]})

    :ok =
      IntervalScheduler.register(is, "b", {:every, 30, :minutes}, {JobSink, :ping, [self(), :b]})

    list = IntervalScheduler.jobs(is)
    assert length(list) == 2
    names = Enum.map(list, fn {n, _, _} -> n end) |> Enum.sort()
    assert names == ["a", "b"]
  end