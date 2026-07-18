  test "100 concurrent tasks each incrementing by 1 produce a final value of 100" do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.increment(:concurrent, 1) end) end)
    |> Task.await_many(5_000)

    assert Metrics.get(:concurrent) == 100
  end