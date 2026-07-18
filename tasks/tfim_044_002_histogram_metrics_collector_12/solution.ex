  test "100 concurrent observations aggregate correctly" do
    1..100
    |> Enum.map(fn _ -> Task.async(fn -> Metrics.observe(:c, 7) end) end)
    |> Task.await_many(5_000)

    summary = Metrics.get(:c)
    assert summary.count == 100
    assert summary.sum == 700
    assert summary.buckets[10] == 100
  end