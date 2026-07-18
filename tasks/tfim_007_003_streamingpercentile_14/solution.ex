  test "quantile is computed over current window only, not full history", %{sp: s} do
    for v <- 1..10, do: StreamingPercentile.push(s, "a", v, 3)

    {:ok, current} = StreamingPercentile.window(s, "a")
    assert current == [8.0, 9.0, 10.0]

    {:ok, med} = StreamingPercentile.percentile(s, "a", 0.5)
    assert med == 9.0
  end