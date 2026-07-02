  test "percentile rejects out-of-range q", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", -0.1)
    assert {:error, :invalid_quantile} = StreamingPercentile.percentile(s, "a", 1.1)
  end