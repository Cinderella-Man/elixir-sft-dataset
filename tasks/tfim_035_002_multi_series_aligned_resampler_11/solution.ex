  test "empty series only forward-fills after it first has a value" do
    # a has a leading gap: no data until bucket 2000
    series = %{a: [{2_500, 7}], b: [{0, 1}, {2_500, 2}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :last, fill: :forward)

    # bucket 0: a has no value yet -> nil even under :forward
    assert row(result, 0) == %{a: nil, b: 1}
    assert row(result, 2_000) == %{a: 7, b: 2}
  end