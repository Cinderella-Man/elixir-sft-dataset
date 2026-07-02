  test "percentile on empty stream returns :no_data", %{sp: s} do
    assert {:error, :no_data} = StreamingPercentile.percentile(s, "x", 0.5)
    assert {:error, :no_data} = StreamingPercentile.percentiles(s, "x", [0.5, 0.95])
    assert {:error, :no_data} = StreamingPercentile.window(s, "x")
  end