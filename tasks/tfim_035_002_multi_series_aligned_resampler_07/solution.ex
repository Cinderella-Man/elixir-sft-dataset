  test "fill: :forward carries each series' own last value forward" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :forward)

    # cpu last at bucket 2000 = 15, mem last at bucket 2000 = 2
    assert row(result, 4_000) == %{cpu: 15, mem: 2}
    assert row(result, 6_000) == %{cpu: 15, mem: 2}
    # Real data still present at 8000
    assert row(result, 8_000) == %{cpu: 99, mem: 7}
  end