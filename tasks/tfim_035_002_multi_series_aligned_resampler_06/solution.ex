  test "fill: :nil leaves each series nil in empty buckets" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :last, fill: :nil)

    assert row(result, 4_000) == %{cpu: nil, mem: nil}
    assert row(result, 6_000) == %{cpu: nil, mem: nil}
  end