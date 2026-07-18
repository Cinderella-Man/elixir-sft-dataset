  test "an always-empty series stays nil in every row under fill: :forward" do
    series = %{a: [], b: [{0, 1}, {2_500, 2}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last, fill: :forward)

    assert result == [{0, %{a: nil, b: 1}}, {2_000, %{a: nil, b: 2}}]
  end