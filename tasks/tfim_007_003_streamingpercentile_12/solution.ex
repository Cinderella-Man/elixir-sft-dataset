  test "percentiles/3 on a single-value window returns same value for every q", %{sp: s} do
    StreamingPercentile.push(s, "a", 7.5, 3)

    {:ok, results} = StreamingPercentile.percentiles(s, "a", [0.0, 0.5, 0.99])

    for q <- [0.0, 0.5, 0.99], do: assert(results[q] == 7.5)
  end