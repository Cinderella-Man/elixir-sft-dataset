  test "a non-integer or negative interval raises ArgumentError" do
    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, 2_000.0, agg: :sum)
    end

    assert_raise ArgumentError, fn ->
      MultiSeriesResampler.resample(@series, -2_000, agg: :sum)
    end
  end