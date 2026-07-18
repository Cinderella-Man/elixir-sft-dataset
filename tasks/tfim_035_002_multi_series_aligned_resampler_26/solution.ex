  test ":count and :sum leave empty buckets nil rather than zero" do
    series = %{cpu: [{0, 5}, {4_500, 7}], mem: [{0, 1}]}

    counted = MultiSeriesResampler.resample(series, @interval, agg: :count, fill: nil)
    assert row(counted, 2_000) == %{cpu: nil, mem: nil}
    assert row(counted, 4_000) == %{cpu: 1, mem: nil}

    summed = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)
    assert row(summed, 2_000) == %{cpu: nil, mem: nil}
    assert row(summed, 4_000) == %{cpu: 7, mem: nil}
  end