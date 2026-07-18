  test "first bucket floors a negative earliest timestamp downwards, not toward zero" do
    # floor(-100 / 2000) * 2000 = -1 * 2000 = -2000
    # floor( 100 / 2000) * 2000 =  0 * 2000 =     0
    data = [{-100, 1}, {100, 2}]
    result = TimeSeriesResampler.resample(data, 2_000, agg: :last, fill: nil)

    assert result == [{-2_000, 1}, {0, 2}]
  end