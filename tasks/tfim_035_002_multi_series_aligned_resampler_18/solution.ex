  test ":max picks per-series largest value in the bucket" do
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :max, fill: nil)

    assert row(result, 0) == %{cpu: 90, mem: 8}
    assert row(result, 2_000) == %{cpu: 7, mem: 6}
  end