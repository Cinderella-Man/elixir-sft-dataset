  test ":min picks per-series smallest value in the bucket" do
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :min, fill: nil)

    assert row(result, 0) == %{cpu: 10, mem: 2}
    assert row(result, 2_000) == %{cpu: 1, mem: 4}
  end