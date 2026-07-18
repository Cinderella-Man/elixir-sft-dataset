  test "100 concurrent increments on the same series total 100" do
    1..100
    |> Enum.map(fn _ ->
      Task.async(fn -> Metrics.increment(:c, %{shard: "a"}, 1) end)
    end)
    |> Task.await_many(5_000)

    assert Metrics.get(:c, %{shard: "a"}) == 100
  end