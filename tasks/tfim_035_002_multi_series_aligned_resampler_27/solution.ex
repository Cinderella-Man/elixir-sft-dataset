  test "options are validated even when the input has no data points" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(%{}, @interval, agg: :median)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(%{a: []}, @interval, fill: :backward)
    end
  end