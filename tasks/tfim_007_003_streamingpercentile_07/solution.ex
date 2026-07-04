  test "q=0 and q=1 return min and max", %{sp: s} do
    for v <- [10, 30, 20, 50, 40], do: StreamingPercentile.push(s, "a", v, 5)

    {:ok, min} = StreamingPercentile.percentile(s, "a", 0.0)
    {:ok, max} = StreamingPercentile.percentile(s, "a", 1.0)

    assert min == 10.0
    assert max == 50.0
  end