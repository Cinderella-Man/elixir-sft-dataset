  test ":sum aggregates each series independently per bucket" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: nil)

    assert row(result, 0) == %{cpu: 30, mem: 1}
    assert row(result, 2_000) == %{cpu: 20, mem: 2}
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end