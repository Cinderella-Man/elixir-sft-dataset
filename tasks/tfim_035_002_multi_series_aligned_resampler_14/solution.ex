  test "input order does not matter" do
    forward = MultiSeriesResampler.resample(@series, @interval, agg: :sum)

    reversed =
      Map.new(@series, fn {name, pts} -> {name, Enum.reverse(pts)} end)

    backward = MultiSeriesResampler.resample(reversed, @interval, agg: :sum)
    assert forward == backward
  end