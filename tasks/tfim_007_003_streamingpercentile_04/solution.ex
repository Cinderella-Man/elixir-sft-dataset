  test "percentiles rejects if any q is out of range", %{sp: s} do
    StreamingPercentile.push(s, "a", 10, 5)

    assert {:error, :invalid_quantile} =
             StreamingPercentile.percentiles(s, "a", [0.5, 2.0])
  end