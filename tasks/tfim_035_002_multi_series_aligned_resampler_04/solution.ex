  test ":count counts per-series points in the bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :count, fill: :nil)

    assert row(result, 0) == %{cpu: 2, mem: 1}
    assert row(result, 2_000) == %{cpu: 2, mem: 1}
    assert row(result, 8_000) == %{cpu: 1, mem: 1}
  end