  test "omitting :fill leaves empty buckets nil" do
    # Bucket 2000 has no cpu points; forward filling would carry 5 into it.
    series = %{cpu: [{0, 5}, {4_500, 7}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last)

    assert result == [{0, %{cpu: 5}}, {2_000, %{cpu: nil}}, {4_000, %{cpu: 7}}]
  end