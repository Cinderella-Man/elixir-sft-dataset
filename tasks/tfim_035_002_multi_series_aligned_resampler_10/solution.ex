  test "a present-but-empty series still appears in every row" do
    series = %{a: [], b: [{0, 5}, {2_500, 9}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert row(result, 0) == %{a: nil, b: 5}
    assert row(result, 2_000) == %{a: nil, b: 9}
  end