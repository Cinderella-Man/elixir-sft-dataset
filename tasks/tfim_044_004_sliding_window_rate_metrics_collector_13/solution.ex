  test "100 concurrent increments in the same second total 100", %{clock: clock} do
    set_time(clock, 7)

    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.increment(:c, 1) end) end)
    |> Task.await_many(5_000)

    assert Metrics.count(:c) == 100
    assert Metrics.rate(:c, 1) == 100
  end