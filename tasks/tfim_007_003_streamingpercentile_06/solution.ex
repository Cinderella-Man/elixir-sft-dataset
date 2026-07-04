  test "single-value window returns that value for any q", %{sp: s} do
    StreamingPercentile.push(s, "a", 42, 10)

    for q <- [0.0, 0.25, 0.5, 0.75, 1.0] do
      {:ok, v} = StreamingPercentile.percentile(s, "a", q)
      assert v == 42.0
    end
  end