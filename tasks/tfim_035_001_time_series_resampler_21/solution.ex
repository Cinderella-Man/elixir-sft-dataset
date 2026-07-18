  test "negative timestamps are assigned to their floored bucket, not a truncated one" do
    # floor(-3000 / 2000) * 2000 = -2 * 2000 = -4000
    # floor(-1000 / 2000) * 2000 = -1 * 2000 = -2000
    data = [{-3_000, 1}, {-1_000, 2}]
    result = TimeSeriesResampler.resample(data, 2_000, agg: :count, fill: nil)

    assert result == [{-4_000, 1}, {-2_000, 1}]
  end