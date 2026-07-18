  test "concurrent increments still land while the owner is suspended", %{clock: clock} do
    set_time(clock, 11)
    owner = Process.whereis(Metrics)
    :sys.suspend(owner)

    tasks = Enum.map(1..20, fn _ -> Task.async(fn -> Metrics.increment(:busy, 2) end) end)
    outcomes = Task.yield_many(tasks, 2_000)
    :sys.resume(owner)

    assert Enum.all?(outcomes, fn {_task, result} -> result == {:ok, :ok} end)
    assert Metrics.count(:busy) == 40
  end