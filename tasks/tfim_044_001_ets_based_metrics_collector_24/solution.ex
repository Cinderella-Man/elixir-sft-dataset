  test "concurrent increments and gauge writes don't interfere with each other" do
    tasks =
      Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c1, 1) end) end) ++
        Enum.map(1..50, fn i -> Task.async(fn -> Metrics.gauge(:g1, i) end) end)

    Task.await_many(tasks, 5_000)

    assert Metrics.get(:c1) == 50
    assert Metrics.get(:g1) in 1..50
  end