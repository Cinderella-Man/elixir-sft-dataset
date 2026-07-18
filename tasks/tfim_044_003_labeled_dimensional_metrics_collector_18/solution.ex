  test "concurrent increments across distinct label sets stay independent" do
    tasks =
      Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c, %{s: 1}, 1) end) end) ++
        Enum.map(1..50, fn _ -> Task.async(fn -> Metrics.increment(:c, %{s: 2}, 1) end) end)

    Task.await_many(tasks, 5_000)

    assert Metrics.get(:c, %{s: 1}) == 50
    assert Metrics.get(:c, %{s: 2}) == 50
    assert Metrics.get(:c) == 100
  end