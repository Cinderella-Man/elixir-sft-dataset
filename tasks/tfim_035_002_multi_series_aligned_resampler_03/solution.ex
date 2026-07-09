  test ":last picks per-series latest value in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: nil)

    assert row(result, 0) == %{cpu: 20, mem: 1}
    assert row(result, 2_000) == %{cpu: 15, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end