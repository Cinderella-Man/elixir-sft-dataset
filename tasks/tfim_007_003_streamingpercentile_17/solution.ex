  test "quantiles handle duplicate values correctly", %{sp: s} do
    for _ <- 1..10, do: StreamingPercentile.push(s, "a", 7.0, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 0.95, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 7.0
    end
  end