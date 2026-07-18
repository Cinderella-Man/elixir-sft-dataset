  test "a negative timestamp floors to the bucket at or below it" do
    # floor(-1500 / 2000) * 2000 = -2000, not 0: truncating toward zero would
    # misplace the point AND shift the grid's first bucket.
    series = %{cpu: [{-1500, 4}, {500, 6}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert Enum.map(result, fn {bucket, _} -> bucket end) == [-2000, 0]
    assert row(result, -2_000) == %{cpu: 4}
    assert row(result, 0) == %{cpu: 6}
  end