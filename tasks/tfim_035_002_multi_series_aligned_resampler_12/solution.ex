  test "empty input map returns empty list" do
    assert MultiSeriesResampler.resample(%{}, @interval, agg: :sum) == []
  end