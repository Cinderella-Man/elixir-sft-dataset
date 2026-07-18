  test "invalid interval and options raise ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, 0, agg: :sum)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, @interval, agg: :median)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, @interval, fill: :backward)
    end
  end